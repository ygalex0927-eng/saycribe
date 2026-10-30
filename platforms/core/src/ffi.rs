//! C ABI：实现 platforms/core/include/saycribe_asr.h（契约 v1）。
#![allow(clippy::missing_safety_doc)]

use crate::asr::Recognizer;
use crate::error::CoreError;
use crate::vad::{Segment, Segmenter, VadConfig};
use std::cell::RefCell;
use std::collections::VecDeque;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;
use std::path::Path;
use std::ptr;

thread_local! {
    static LAST_ERROR: RefCell<String> = RefCell::new(String::new());
    static LAST_ERROR_C: RefCell<Option<CString>> = RefCell::new(None);
}

fn set_err(s: impl Into<String>) {
    LAST_ERROR.with(|e| *e.borrow_mut() = s.into());
}

fn clear_err() {
    LAST_ERROR.with(|e| e.borrow_mut().clear());
}

#[repr(C)]
pub struct ScResult {
    pub text: *mut c_char,
    pub lang: *mut c_char,
    pub audio_seconds: f64,
    pub decode_ms: u64,
    pub start_sample: i64,
}

#[repr(C)]
pub struct ScSegment {
    pub samples: *const f32,
    pub n: i32,
    pub start_sample: i64,
}

#[repr(C)]
pub struct ScRecognizerConfig {
    pub model_dir: *const c_char,
    pub language: *const c_char,
    pub num_threads: i32,
    pub provider: *const c_char,
    pub use_itn: i32,
}

#[repr(C)]
pub struct ScVadConfig {
    pub silero_model: *const c_char,
    pub threshold: f32,
    pub min_silence_sec: f32,
    pub min_speech_sec: f32,
    pub max_speech_sec: f32,
    pub buffer_sec: f32,
}

pub struct ScRecognizer {
    inner: Recognizer,
}

pub struct ScSegmenter {
    inner: Segmenter,
    ready: VecDeque<Segment>,
    front: Option<Segment>,
}

fn cstr<'a>(p: *const c_char) -> Option<&'a str> {
    if p.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(p) }.to_str().ok()
}

fn map_err(e: CoreError) -> i32 {
    let msg = e.to_string();
    set_err(&msg);
    match &e {
        CoreError::Model(m) if m.contains("模型缺失") => -2,
        CoreError::Model(_) => -3,
        CoreError::Asr(m) if m.contains("BUSY") => -7,
        CoreError::Asr(m) if m.contains("300") => -5,
        CoreError::Asr(m) if m.contains("采样率") => -4,
        CoreError::Asr(_) => -6,
        CoreError::Io(_) => -2,
        _ => -99,
    }
}

fn to_c_string(s: &str) -> *mut c_char {
    CString::new(s.replace('\0', ""))
        .map(|c| c.into_raw())
        .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub extern "C" fn sc_asr_abi_version() -> i32 {
    1
}

#[no_mangle]
pub extern "C" fn sc_status_message(s: i32) -> *const c_char {
    static OK: &[u8] = b"ok\0";
    static E1: &[u8] = b"invalid arg\0";
    static E2: &[u8] = b"model missing\0";
    static E3: &[u8] = b"model load failed\0";
    static E4: &[u8] = b"sample rate not 16000\0";
    static E5: &[u8] = b"audio too long (>300s)\0";
    static E6: &[u8] = b"decode failed\0";
    static E7: &[u8] = b"recognizer busy\0";
    static E8: &[u8] = b"cancelled\0";
    static E99: &[u8] = b"internal error\0";
    static EU: &[u8] = b"unknown\0";
    let m: &'static [u8] = match s {
        0 => OK,
        -1 => E1,
        -2 => E2,
        -3 => E3,
        -4 => E4,
        -5 => E5,
        -6 => E6,
        -7 => E7,
        -8 => E8,
        -99 => E99,
        _ => EU,
    };
    m.as_ptr() as *const c_char
}

#[no_mangle]
pub extern "C" fn sc_last_error() -> *const c_char {
    LAST_ERROR.with(|e| {
        let s = e.borrow().replace('\0', "");
        LAST_ERROR_C.with(|b| {
            *b.borrow_mut() = Some(CString::new(s).unwrap_or_default());
        });
    });
    LAST_ERROR_C.with(|b| b.borrow().as_ref().map(|x| x.as_ptr()).unwrap_or(ptr::null()))
}

#[no_mangle]
pub unsafe extern "C" fn sc_recognizer_config_default(cfg: *mut ScRecognizerConfig) {
    if cfg.is_null() {
        return;
    }
    (*cfg).model_dir = ptr::null();
    (*cfg).language = ptr::null();
    (*cfg).num_threads = 4;
    (*cfg).provider = ptr::null();
    (*cfg).use_itn = 1;
}

#[no_mangle]
pub unsafe extern "C" fn sc_recognizer_create(
    cfg: *const ScRecognizerConfig,
    out: *mut *mut ScRecognizer,
) -> i32 {
    clear_err();
    if cfg.is_null() || out.is_null() {
        set_err("cfg/out null");
        return -1;
    }
    *out = ptr::null_mut();
    let c = &*cfg;
    let Some(dir) = cstr(c.model_dir) else {
        set_err("model_dir invalid");
        return -1;
    };
    let lang = cstr(c.language).unwrap_or("auto");
    let provider = cstr(c.provider);
    let use_itn = c.use_itn != 0;
    match Recognizer::with_itn(Path::new(dir), lang, c.num_threads, provider, use_itn) {
        Ok(r) => {
            *out = Box::into_raw(Box::new(ScRecognizer { inner: r }));
            0
        }
        Err(e) => map_err(e),
    }
}

#[no_mangle]
pub unsafe extern "C" fn sc_recognizer_destroy(r: *mut ScRecognizer) {
    if !r.is_null() {
        drop(Box::from_raw(r));
    }
}

#[no_mangle]
pub unsafe extern "C" fn sc_recognizer_transcribe(
    r: *mut ScRecognizer,
    pcm: *const f32,
    n: i32,
    sample_rate: i32,
    out: *mut *mut ScResult,
) -> i32 {
    clear_err();
    if r.is_null() || out.is_null() || (n > 0 && pcm.is_null()) || n < 0 {
        set_err("invalid arg");
        return -1;
    }
    *out = ptr::null_mut();
    if sample_rate != 16_000 {
        set_err(format!("sample rate not 16000: {sample_rate}"));
        return -4;
    }
    let slice = if n == 0 {
        &[][..]
    } else {
        std::slice::from_raw_parts(pcm, n as usize)
    };
    match (*r).inner.transcribe(slice) {
        Ok(t) => {
            let res = Box::new(ScResult {
                text: to_c_string(&t.text),
                lang: to_c_string(&t.lang),
                audio_seconds: t.audio_seconds,
                decode_ms: t.decode_ms,
                start_sample: t.start_sample,
            });
            *out = Box::into_raw(res);
            0
        }
        Err(e) => map_err(e),
    }
}

#[no_mangle]
pub unsafe extern "C" fn sc_result_free(res: *mut ScResult) {
    if res.is_null() {
        return;
    }
    let res = Box::from_raw(res);
    if !res.text.is_null() {
        drop(CString::from_raw(res.text));
    }
    if !res.lang.is_null() {
        drop(CString::from_raw(res.lang));
    }
}

#[no_mangle]
pub unsafe extern "C" fn sc_vad_config_default(cfg: *mut ScVadConfig) {
    if cfg.is_null() {
        return;
    }
    (*cfg).silero_model = ptr::null();
    (*cfg).threshold = 0.5;
    (*cfg).min_silence_sec = 0.45;
    (*cfg).min_speech_sec = 0.25;
    (*cfg).max_speech_sec = 12.0;
    (*cfg).buffer_sec = 120.0;
}

#[no_mangle]
pub unsafe extern "C" fn sc_segmenter_create(
    cfg: *const ScVadConfig,
    out: *mut *mut ScSegmenter,
) -> i32 {
    clear_err();
    if cfg.is_null() || out.is_null() {
        set_err("cfg/out null");
        return -1;
    }
    *out = ptr::null_mut();
    let c = &*cfg;
    let Some(path) = cstr(c.silero_model) else {
        set_err("silero_model invalid");
        return -1;
    };
    let vc = VadConfig {
        threshold: if c.threshold > 0.0 { c.threshold } else { 0.5 },
        min_silence: if c.min_silence_sec > 0.0 {
            c.min_silence_sec
        } else {
            0.45
        },
        min_speech: if c.min_speech_sec > 0.0 {
            c.min_speech_sec
        } else {
            0.25
        },
        max_speech: if c.max_speech_sec > 0.0 {
            c.max_speech_sec
        } else {
            12.0
        },
        buffer_sec: if c.buffer_sec > 0.0 { c.buffer_sec } else { 120.0 },
    };
    match Segmenter::with_config(Path::new(path), vc) {
        Ok(s) => {
            *out = Box::into_raw(Box::new(ScSegmenter {
                inner: s,
                ready: VecDeque::new(),
                front: None,
            }));
            0
        }
        Err(e) => map_err(e),
    }
}

#[no_mangle]
pub unsafe extern "C" fn sc_segmenter_destroy(s: *mut ScSegmenter) {
    if !s.is_null() {
        drop(Box::from_raw(s));
    }
}

#[no_mangle]
pub unsafe extern "C" fn sc_segmenter_push(
    s: *mut ScSegmenter,
    pcm: *const f32,
    n: i32,
    ready: *mut i32,
) -> i32 {
    clear_err();
    if s.is_null() || (n > 0 && pcm.is_null()) || n < 0 {
        set_err("invalid arg");
        return -1;
    }
    let seg = &mut *s;
    let slice = if n == 0 {
        &[][..]
    } else {
        std::slice::from_raw_parts(pcm, n as usize)
    };
    let got = seg.inner.push(slice);
    seg.ready.extend(got);
    if !ready.is_null() {
        *ready = seg.ready.len() as i32;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn sc_segmenter_finish(s: *mut ScSegmenter, ready: *mut i32) -> i32 {
    clear_err();
    if s.is_null() {
        set_err("invalid arg");
        return -1;
    }
    let seg = &mut *s;
    let got = seg.inner.finish();
    seg.ready.extend(got);
    if !ready.is_null() {
        *ready = seg.ready.len() as i32;
    }
    0
}

#[no_mangle]
pub unsafe extern "C" fn sc_segmenter_pop(s: *mut ScSegmenter, seg: *mut ScSegment) -> i32 {
    if s.is_null() || seg.is_null() {
        return 0;
    }
    let this = &mut *s;
    this.front = this.ready.pop_front();
    match this.front.as_ref() {
        Some(g) => {
            (*seg).samples = g.samples.as_ptr();
            (*seg).n = g.samples.len() as i32;
            (*seg).start_sample = g.start;
            1
        }
        None => {
            (*seg).samples = ptr::null();
            (*seg).n = 0;
            (*seg).start_sample = 0;
            0
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn sc_segmenter_speaking(s: *const ScSegmenter) -> i32 {
    if s.is_null() {
        return 0;
    }
    if (*s).inner.speaking() {
        1
    } else {
        0
    }
}

#[no_mangle]
pub unsafe extern "C" fn sc_segmenter_reset(s: *mut ScSegmenter) {
    if s.is_null() {
        return;
    }
    let this = &mut *s;
    this.ready.clear();
    this.front = None;
    this.inner.reset();
}
