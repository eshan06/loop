// Browser-side photo prep: the server takes JPEG only, 5 MB max. Resize like the iOS app does.

export class UnreadablePhotoError extends Error {
  constructor() {
    super("Couldn't read that photo. Try a JPEG or PNG.")
    this.name = 'UnreadablePhotoError'
  }
}

export const MAX_SIDE = 1600
export const JPEG_QUALITY = 0.85

/** Target size keeping aspect ratio, longest side at most `max`, never upscaling. */
export function fitWithin(w: number, h: number, max = MAX_SIDE): { width: number; height: number } {
  const longest = Math.max(w, h)
  if (longest <= max) return { width: w, height: h }
  const k = max / longest
  return { width: Math.max(1, Math.round(w * k)), height: Math.max(1, Math.round(h * k)) }
}

async function decode(file: Blob): Promise<{ source: CanvasImageSource; width: number; height: number; close?: () => void }> {
  if (typeof createImageBitmap === 'function') {
    try {
      const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' })
      return { source: bmp, width: bmp.width, height: bmp.height, close: () => bmp.close() }
    } catch {
      /* fall through to <img> */
    }
  }
  const url = URL.createObjectURL(file)
  try {
    const img = new Image()
    img.decoding = 'async'
    img.src = url
    await img.decode()
    return { source: img, width: img.naturalWidth, height: img.naturalHeight }
  } finally {
    URL.revokeObjectURL(url)
  }
}

/** Draw the file onto a canvas (longest side <= 1600) and return a JPEG blob. */
export async function resizeToJpeg(file: Blob, max = MAX_SIDE, quality = JPEG_QUALITY): Promise<Blob> {
  let decoded
  try {
    decoded = await decode(file)
  } catch {
    throw new UnreadablePhotoError()
  }
  if (!decoded.width || !decoded.height) throw new UnreadablePhotoError()
  const { width, height } = fitWithin(decoded.width, decoded.height, max)
  const canvas = document.createElement('canvas')
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext('2d')
  if (!ctx) throw new UnreadablePhotoError()
  ctx.fillStyle = '#fff' // PNGs with transparency would otherwise turn black
  ctx.fillRect(0, 0, width, height)
  ctx.drawImage(decoded.source, 0, 0, width, height)
  decoded.close?.()
  const blob = await new Promise<Blob | null>((res) => canvas.toBlob(res, 'image/jpeg', quality))
  if (!blob) throw new UnreadablePhotoError()
  return blob
}
