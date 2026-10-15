use std::io::Cursor;

use png::{BitDepth, ColorType, Decoder, Transformations};

#[derive(Clone, Debug, PartialEq)]
pub struct Raster<T> {
    pub width: usize,
    pub height: usize,
    pub samples: Vec<T>,
}

impl<T> Raster<T> {
    fn new(width: usize, height: usize, samples: Vec<T>) -> Result<Self, String> {
        if width < 2 || height < 2 {
            return Err(format!(
                "raster dimensions must be at least 2x2, got {width}x{height}"
            ));
        }
        let expected = width
            .checked_mul(height)
            .ok_or_else(|| "raster dimensions overflow addressable memory".to_string())?;
        if samples.len() != expected {
            return Err(format!(
                "raster sample count does not match dimensions: expected {expected}, got {}",
                samples.len()
            ));
        }
        Ok(Self {
            width,
            height,
            samples,
        })
    }
}

#[derive(Clone, Debug, PartialEq)]
pub struct TerrainData {
    /// Elevation samples are in metres, with each raster retaining its own dimensions.
    pub elevation_m: Raster<f32>,
    /// Biome IDs are categorical bytes and are never interpolated.
    pub biome_ids: Raster<u8>,
}

impl TerrainData {
    pub fn from_layers(
        elevation_bytes: &[u8],
        biome_png_bytes: &[u8],
        elevation_variance_m: f32,
        valid_biome_ids: Option<&[u8]>,
    ) -> Result<Self, String> {
        if !elevation_variance_m.is_finite() || elevation_variance_m <= 0.0 {
            return Err("elevation variance must be a finite positive number".into());
        }
        let mut elevation_m = decode_cylh(elevation_bytes)?;
        for sample in &mut elevation_m.samples {
            *sample *= elevation_variance_m;
        }
        let biome_ids = decode_biome_png(biome_png_bytes)?;
        if let Some(valid_ids) = valid_biome_ids {
            let mut allowed = [false; 256];
            for id in valid_ids {
                allowed[*id as usize] = true;
            }
            if let Some(id) = biome_ids.samples.iter().find(|id| !allowed[**id as usize]) {
                return Err(format!(
                    "biome layer contains an ID absent from map_config.json: {id}"
                ));
            }
        }
        Ok(Self {
            elevation_m,
            biome_ids,
        })
    }

    pub fn elevation_at(
        &self,
        theta: f64,
        z_m: f64,
        cylinder_length_m: f64,
    ) -> Result<f32, String> {
        if !theta.is_finite()
            || !z_m.is_finite()
            || !cylinder_length_m.is_finite()
            || cylinder_length_m <= 0.0
        {
            return Err("terrain query coordinates and cylinder length must be finite; length must be positive".into());
        }
        let u = theta.rem_euclid(std::f64::consts::TAU) / std::f64::consts::TAU;
        let v = (z_m / cylinder_length_m + 0.5).clamp(0.0, 1.0);
        let raster = &self.elevation_m;
        let x = u * raster.width as f64;
        let y = v * (raster.height - 1) as f64;
        let x0 = x.floor() as usize % raster.width;
        let x1 = (x0 + 1) % raster.width;
        let y0 = y.floor() as usize;
        let y1 = (y0 + 1).min(raster.height - 1);
        let fx = (x - x.floor()) as f32;
        let fy = (y - y.floor()) as f32;
        let h00 = raster.samples[y0 * raster.width + x0];
        let h10 = raster.samples[y0 * raster.width + x1];
        let h01 = raster.samples[y1 * raster.width + x0];
        let h11 = raster.samples[y1 * raster.width + x1];
        Ok(lerp(lerp(h00, h10, fx), lerp(h01, h11, fx), fy))
    }

    pub fn biome_id_at(&self, theta: f64, z_m: f64, cylinder_length_m: f64) -> Result<u8, String> {
        if !theta.is_finite()
            || !z_m.is_finite()
            || !cylinder_length_m.is_finite()
            || cylinder_length_m <= 0.0
        {
            return Err("terrain query coordinates and cylinder length must be finite; length must be positive".into());
        }
        let raster = &self.biome_ids;
        let u = theta.rem_euclid(std::f64::consts::TAU) / std::f64::consts::TAU;
        let v = (z_m / cylinder_length_m + 0.5).clamp(0.0, 1.0);
        let x = ((u * raster.width as f64).round() as usize) % raster.width;
        let y = ((v * (raster.height - 1) as f64).round() as usize).min(raster.height - 1);
        Ok(raster.samples[y * raster.width + x])
    }
}

pub fn decode_cylh(bytes: &[u8]) -> Result<Raster<f32>, String> {
    if bytes.len() < 12 || &bytes[..4] != b"CYLH" {
        return Err("elevation layer must begin with CYLH and contain a 12-byte header".into());
    }
    let width = u32::from_le_bytes(bytes[4..8].try_into().unwrap()) as usize;
    let height = u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;
    let count = checked_sample_count(width, height, 536_870_912)?;
    let data_len = count
        .checked_mul(4)
        .ok_or_else(|| "elevation byte count overflow".to_string())?;
    let expected_len = 12usize
        .checked_add(data_len)
        .ok_or_else(|| "elevation byte count overflow".to_string())?;
    if bytes.len() != expected_len {
        return Err(format!(
            "elevation byte count does not match its dimensions: expected {expected_len}, got {}",
            bytes.len()
        ));
    }
    let mut samples = Vec::with_capacity(count);
    for chunk in bytes[12..].chunks_exact(4) {
        let sample = f32::from_le_bytes(chunk.try_into().unwrap());
        if !sample.is_finite() || !(0.0..=1.0).contains(&sample) {
            return Err("elevation samples must be finite normalized values from 0 to 1".into());
        }
        samples.push(sample);
    }
    Raster::new(width, height, samples)
}

pub fn decode_biome_png(bytes: &[u8]) -> Result<Raster<u8>, String> {
    let mut decoder = Decoder::new(Cursor::new(bytes));
    decoder.set_transformations(Transformations::IDENTITY);
    let mut reader = decoder
        .read_info()
        .map_err(|e| format!("cannot decode biome PNG: {e}"))?;
    let mut frame = vec![0; reader.output_buffer_size()];
    let info = reader
        .next_frame(&mut frame)
        .map_err(|e| format!("cannot decode biome PNG frame: {e}"))?;
    let frame = &frame[..info.buffer_size()];
    let width = info.width as usize;
    let height = info.height as usize;
    let count = checked_sample_count(width, height, 536_870_912)?;
    let samples = match (info.color_type, info.bit_depth) {
        (ColorType::Grayscale, BitDepth::Eight) => frame.to_vec(),
        (ColorType::Grayscale, BitDepth::Sixteen) => {
            let mut ids = Vec::with_capacity(count);
            for pair in frame.chunks_exact(2) {
                let value = u16::from_be_bytes([pair[0], pair[1]]);
                if value > u8::MAX as u16 {
                    return Err(format!("16-bit grayscale biome ID exceeds 255: {value}"));
                }
                ids.push(value as u8);
            }
            ids
        }
        (ColorType::Indexed, depth) => unpack_palette_indices(frame, width, height, depth)?,
        (color, depth) => {
            return Err(format!(
                "unsupported biome PNG encoding: {color:?} with {depth:?}"
            ));
        }
    };
    if samples.len() != count {
        return Err("decoded biome PNG sample count does not match dimensions".into());
    }
    Raster::new(width, height, samples)
}

fn unpack_palette_indices(
    bytes: &[u8],
    width: usize,
    height: usize,
    depth: BitDepth,
) -> Result<Vec<u8>, String> {
    let bits_per_index = match depth {
        BitDepth::One => 1,
        BitDepth::Two => 2,
        BitDepth::Four => 4,
        BitDepth::Eight => 8,
        _ => return Err("indexed biome PNG must use 1, 2, 4 or 8 bits per pixel".into()),
    };
    let row_bytes = (width * bits_per_index + 7) / 8;
    if bytes.len() != row_bytes * height {
        return Err("indexed biome PNG byte count does not match dimensions".into());
    }
    if bits_per_index == 8 {
        return Ok(bytes.to_vec());
    }
    let mask = (1u8 << bits_per_index) - 1;
    let per_byte = 8 / bits_per_index;
    let mut output = Vec::with_capacity(width * height);
    for y in 0..height {
        let row = &bytes[y * row_bytes..(y + 1) * row_bytes];
        for x in 0..width {
            let shift = 8 - bits_per_index * (x % per_byte + 1);
            output.push((row[x / per_byte] >> shift) & mask);
        }
    }
    Ok(output)
}

fn checked_sample_count(width: usize, height: usize, max_samples: usize) -> Result<usize, String> {
    if width < 2 || height < 2 || width > 32768 || height > 32768 {
        return Err(format!("raster dimensions are invalid: {width}x{height}"));
    }
    let count = width
        .checked_mul(height)
        .ok_or_else(|| "raster dimensions overflow addressable memory".to_string())?;
    if count > max_samples {
        return Err(format!(
            "raster exceeds {max_samples} samples: {width}x{height}"
        ));
    }
    Ok(count)
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}

#[cfg(test)]
mod tests {
    use super::*;

    fn cylh(width: u32, height: u32, values: &[f32]) -> Vec<u8> {
        let mut bytes = b"CYLH".to_vec();
        bytes.extend(width.to_le_bytes());
        bytes.extend(height.to_le_bytes());
        for value in values {
            bytes.extend(value.to_le_bytes());
        }
        bytes
    }

    #[test]
    fn decodes_cylh_and_rejects_nonfinite_samples() {
        let raster = decode_cylh(&cylh(2, 2, &[0.0, 0.25, 0.75, 1.0])).unwrap();
        assert_eq!(raster.width, 2);
        assert_eq!(raster.samples, vec![0.0, 0.25, 0.75, 1.0]);
        assert!(decode_cylh(&cylh(2, 2, &[0.0, 0.25, f32::NAN, 1.0])).is_err());
    }

    #[test]
    fn bilinear_elevation_wraps_u_and_clamps_v() {
        let data = TerrainData {
            elevation_m: Raster::new(2, 2, vec![0.0, 10.0, 20.0, 30.0]).unwrap(),
            biome_ids: Raster::new(2, 2, vec![1, 2, 3, 4]).unwrap(),
        };
        let seam = data.elevation_at(0.0, 0.0, 10.0).unwrap();
        assert!((seam - 10.0).abs() < 1e-6);
        assert_eq!(
            data.elevation_at(std::f64::consts::TAU, -100.0, 10.0)
                .unwrap(),
            0.0
        );
        assert_eq!(
            data.elevation_at(-std::f64::consts::FRAC_PI_2, 100.0, 10.0)
                .unwrap(),
            25.0
        );
    }

    #[test]
    fn rejects_invalid_dimensions_and_lengths() {
        assert!(decode_cylh(b"CYLH\0").is_err());
        assert!(Raster::new(1, 2, vec![0u8, 0]).is_err());
    }

    #[test]
    fn indexed_png_returns_palette_indices_not_palette_colors() {
        let mut encoded = Vec::new();
        {
            let mut encoder = png::Encoder::new(&mut encoded, 2, 2);
            encoder.set_color(ColorType::Indexed);
            encoder.set_depth(BitDepth::Eight);
            encoder.set_palette(vec![250, 0, 0, 0, 250, 0, 0, 0, 250, 90, 90, 90]);
            let mut writer = encoder.write_header().unwrap();
            writer.write_image_data(&[3, 1, 2, 0]).unwrap();
            writer.finish().unwrap();
        }
        let decoded = decode_biome_png(&encoded).unwrap();
        assert_eq!(decoded.samples, vec![3, 1, 2, 0]);
    }
}
