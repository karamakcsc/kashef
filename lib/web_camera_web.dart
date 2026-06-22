// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Opens a live webcam overlay in the browser.
///
/// Return value `(List<int>? bytes, bool shouldFallback)`:
///   (bytes, false)  — user captured; bytes = JPEG image data
///   (null,  false)  — user pressed Cancel; caller does nothing
///   (null,  true )  — camera unavailable / permission denied;
///                     caller should show file picker as fallback
///
/// Never throws — all errors are shown as in-overlay messages.
Future<(List<int>?, bool)> showWebCameraOverlay() async {
  // ── Secure context (camera requires HTTPS or localhost) ───────────────────
  bool isSecure = false;
  try {
    isSecure = web.window.isSecureContext;
  } catch (_) {}

  if (!isSecure) {
    _toast('⚠️ Camera requires HTTPS. Opening file picker instead.');
    return (null, true);
  }

  // ── Browser support check ─────────────────────────────────────────────────
  try {
    web.window.navigator.mediaDevices;
  } catch (_) {
    _toast('❌ Camera API not supported in this browser.');
    return (null, true);
  }

  // ── Build overlay DOM ──────────────────────────────────────────────────────
  final overlay = web.document.createElement('div') as web.HTMLDivElement;
  overlay.id = 'kcsc-cam-overlay';
  // Focusable so keyboard events reach the overlay (Escape to close)
  overlay.setAttribute('tabindex', '-1');
  overlay.style.cssText = _css([
    'position:fixed', 'inset:0', 'z-index:999999',
    'background:rgba(0,0,0,0.92)',
    'display:flex', 'flex-direction:column',
    'align-items:center', 'justify-content:center',
    'gap:20px', 'padding:24px', 'box-sizing:border-box',
    'outline:none',
  ]);

  // Title
  final title = _div(_css([
    'color:#F8FAFC', 'font-size:18px', 'font-weight:600',
    'font-family:system-ui,sans-serif',
  ]));
  title.textContent = '📷 Take a Photo';

  // Live video preview
  final video = web.document.createElement('video') as web.HTMLVideoElement;
  video.autoplay = true;
  video.muted    = true;
  video.style.cssText = _css([
    'width:min(80vw,640px)', 'height:auto', 'max-height:60vh',
    'border-radius:12px', 'background:#0F172A',
    'border:2px solid #3B82F6', 'object-fit:cover', 'display:block',
  ]);

  // Status / hint
  final status = web.document.createElement('p') as web.HTMLParagraphElement;
  status.style.cssText = _css([
    'color:#94A3B8', 'font-size:13px', 'margin:0',
    'font-family:system-ui,sans-serif', 'text-align:center',
    'max-width:480px', 'white-space:pre-wrap',
  ]);
  status.textContent = 'Initializing camera…';

  // Buttons row
  final btnRow = _div('display:flex;gap:12px;flex-wrap:wrap;justify-content:center;');

  // Capture (disabled until stream ready)
  final captureBtn = web.document.createElement('button') as web.HTMLButtonElement;
  captureBtn.textContent = '📷  Capture';
  captureBtn.disabled    = true;
  captureBtn.style.cssText = _css([
    'padding:12px 32px', 'border-radius:50px', 'border:none',
    'cursor:not-allowed', 'background:#3B82F6', 'color:#fff',
    'font-size:15px', 'font-weight:600', 'font-family:system-ui,sans-serif',
    'opacity:0.45', 'transition:opacity 0.2s,cursor 0.2s',
  ]);

  // Cancel
  final cancelBtn = web.document.createElement('button') as web.HTMLButtonElement;
  cancelBtn.textContent = '✕  Cancel';
  cancelBtn.style.cssText = _css([
    'padding:12px 24px', 'border-radius:50px',
    'border:2px solid #475569', 'cursor:pointer',
    'background:transparent', 'color:#94A3B8',
    'font-size:14px', 'font-family:system-ui,sans-serif',
  ]);

  // Hidden canvas for frame capture — not added to DOM
  final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement;

  // Assemble overlay
  btnRow.appendChild(captureBtn);
  btnRow.appendChild(cancelBtn);
  overlay.appendChild(title);
  overlay.appendChild(video);
  overlay.appendChild(status);
  overlay.appendChild(btnRow);
  web.document.body?.appendChild(overlay);

  // Focus the overlay so it receives keyboard events
  Future.delayed(const Duration(milliseconds: 50), () {
    try { overlay.focus(); } catch (_) {}
  });

  // ── State ──────────────────────────────────────────────────────────────────
  final completer = Completer<(List<int>?, bool)>();
  web.MediaStream? stream;
  bool closed = false;

  void close((List<int>?, bool) result) {
    if (closed) return;
    closed = true;
    try { stream?.getTracks().toDart.forEach((t) => t.stop()); } catch (_) {}
    overlay.remove();
    if (!completer.isCompleted) completer.complete(result);
  }

  // ── Escape key on the focused overlay ─────────────────────────────────────
  overlay.addEventListener('keydown', (web.Event evt) {
    if ((evt as web.KeyboardEvent).key == 'Escape') close((null, false));
  }.toJS);

  // ── Request camera stream ─────────────────────────────────────────────────
  try {
    final constraints = web.MediaStreamConstraints(
      video: true.toJS,
      audio: false.toJS,
    );
    stream = await web.window.navigator.mediaDevices
        .getUserMedia(constraints)
        .toDart;

    video.srcObject = stream;

    // Wait for video dimensions to be available
    final metaCompleter = Completer<void>();
    video.addEventListener('loadedmetadata', (web.Event _) {
      if (!metaCompleter.isCompleted) metaCompleter.complete();
    }.toJS);
    await metaCompleter.future
        .timeout(const Duration(seconds: 5), onTimeout: () {});

    captureBtn.disabled = false;
    captureBtn.style.opacity = '1';
    captureBtn.style.cursor  = 'pointer';
    status.textContent = 'Camera ready — click Capture to take a photo.';
  } catch (e) {
    final msg = e.toString().toLowerCase();
    String userMsg;
    if (msg.contains('notallowed') || msg.contains('permissiondenied') ||
        msg.contains('permission denied')) {
      userMsg = '❌ Camera permission denied.\n'
          'Allow camera access in browser settings and try again.';
    } else if (msg.contains('notfound') || msg.contains('devicenotfound')) {
      userMsg = '❌ No camera found on this device.';
    } else if (msg.contains('notreadable') || msg.contains('trackstart') ||
               msg.contains('already in use')) {
      userMsg = '❌ Camera is in use by another app.\n'
          'Close other tabs or apps using the camera and retry.';
    } else {
      userMsg = '❌ Camera unavailable — opening file picker instead…';
    }
    status.textContent = userMsg;
    await Future.delayed(const Duration(seconds: 2));
    close((null, true)); // signal: show file picker fallback
    return completer.future;
  }

  // ── Capture handler ────────────────────────────────────────────────────────
  captureBtn.addEventListener('click', (web.Event _) {
    try {
      final w = video.videoWidth;
      final h = video.videoHeight;
      if (w == 0 || h == 0) {
        status.textContent = '⚠️ Video not ready yet — try again.';
        return;
      }
      canvas.width  = w;
      canvas.height = h;

      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D?;
      if (ctx == null) {
        status.textContent = '❌ Canvas context unavailable.';
        return;
      }

      // HTMLVideoElement is a valid CanvasImageSource at the JS level.
      ctx.drawImage(video as web.CanvasImageSource, 0, 0);

      final dataUrl = canvas.toDataURL('image/jpeg', 0.85.toJS);
      final parts   = dataUrl.split(',');
      if (parts.length < 2) {
        status.textContent = '❌ Failed to encode image.';
        return;
      }
      close((List<int>.from(base64Decode(parts[1])), false));
    } catch (e) {
      status.textContent = '❌ Capture failed: $e';
    }
  }.toJS);

  // ── Cancel handler ─────────────────────────────────────────────────────────
  cancelBtn.addEventListener('click', (web.Event _) {
    close((null, false));
  }.toJS);

  return completer.future;
}

// ── Private helpers ───────────────────────────────────────────────────────────

/// Joins CSS rule strings with semicolons.
String _css(List<String> rules) => rules.join(';');

/// Creates a `<div>` with the given inline CSS.
web.HTMLDivElement _div(String css) {
  final el = web.document.createElement('div') as web.HTMLDivElement;
  el.style.cssText = css;
  return el;
}

/// Shows a brief auto-dismissing toast at the bottom of the viewport.
void _toast(String message) {
  try {
    final toast = web.document.createElement('div') as web.HTMLDivElement;
    toast.textContent = message;
    toast.style.cssText = _css([
      'position:fixed', 'bottom:24px', 'left:50%',
      'transform:translateX(-50%)',
      'background:#1E293B', 'color:#F8FAFC',
      'padding:12px 24px', 'border-radius:8px',
      'font-size:14px', 'font-family:system-ui,sans-serif',
      'z-index:999999', 'white-space:nowrap',
      'box-shadow:0 4px 12px rgba(0,0,0,0.4)',
    ]);
    web.document.body?.appendChild(toast);
    Future.delayed(const Duration(seconds: 3), () {
      try { toast.remove(); } catch (_) {}
    });
  } catch (_) {}
}
