// SPDX-License-Identifier: MIT

//! Image header checks: PNG, WebP or JPEG only, within a byte and a pixel cap.

use crate::policy::NetError;

/// Largest image accepted, in bytes (2 MiB).
pub const MAX_IMAGE_BYTES: usize = 2 * 1024 * 1024;

/// Largest image accepted, in pixels (2048 × 2048).
pub const MAX_IMAGE_PIXELS: u64 = 4_194_304;

const PNG_MAGIC: &[u8] = b"\x89PNG\r\n\x1a\n";
const JPEG_MAGIC: &[u8] = &[0xff, 0xd8, 0xff];

/// Checks an image header and returns its width and height.
///
/// Only PNG, WebP and JPEG are accepted, by magic bytes. An image with a zero
/// width or height, over `max_bytes` or over `max_pixels` is refused.
pub fn check_image_header(
    bytes: &[u8],
    max_bytes: usize,
    max_pixels: u64,
) -> Result<(u32, u32), NetError> {
    if bytes.len() > max_bytes {
        return Err(NetError::ImageBytes {
            size: bytes.len(),
            limit: max_bytes,
        });
    }
    if !is_supported(bytes) {
        return Err(NetError::ImageFormat);
    }

    let size = imagesize::blob_size(bytes).map_err(|_| NetError::ImageFormat)?;
    let width = u32::try_from(size.width).map_err(|_| NetError::ImageFormat)?;
    let height = u32::try_from(size.height).map_err(|_| NetError::ImageFormat)?;
    if width == 0 || height == 0 {
        return Err(NetError::ImageFormat);
    }
    let pixels = u64::from(width) * u64::from(height);
    if pixels > max_pixels {
        return Err(NetError::ImagePixels {
            pixels,
            limit: max_pixels,
        });
    }
    Ok((width, height))
}

/// Recognizes PNG, WebP and JPEG by their magic bytes.
fn is_supported(bytes: &[u8]) -> bool {
    bytes.starts_with(PNG_MAGIC)
        || bytes.starts_with(JPEG_MAGIC)
        || (bytes.starts_with(b"RIFF") && bytes.len() >= 12 && &bytes[8..12] == b"WEBP")
}
