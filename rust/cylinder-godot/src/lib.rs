use cylinder_core::terrain::{Raster, decode_biome_png, decode_cylh};
use godot::classes::RefCounted;
use godot::prelude::*;

struct CylinderExtension;

#[gdextension]
unsafe impl ExtensionLibrary for CylinderExtension {}

#[derive(GodotClass)]
#[class(base=RefCounted)]
struct RustTerrainData {
    #[base]
    _base: Base<RefCounted>,
    elevation: Option<Raster<f32>>,
    biome_ids: Option<Raster<u8>>,
    last_error: GString,
}

#[godot_api]
impl IRefCounted for RustTerrainData {
    fn init(base: Base<RefCounted>) -> Self {
        Self {
            _base: base,
            elevation: None,
            biome_ids: None,
            last_error: GString::new(),
        }
    }
}

#[godot_api]
impl RustTerrainData {
    /// Decode the project's CYLH float32 format and retain elevations in metres.
    #[func]
    fn load_elevation_bytes(&mut self, bytes: PackedByteArray, elevation_variance_m: f64) -> bool {
        match decode_cylh(bytes.as_slice()) {
            Ok(mut raster) if elevation_variance_m.is_finite() && elevation_variance_m > 0.0 => {
                for value in &mut raster.samples {
                    *value *= elevation_variance_m as f32;
                }
                self.elevation = Some(raster);
                self.last_error = GString::new();
                true
            }
            Ok(_) => self.fail("elevation variance must be finite and positive"),
            Err(error) => self.fail(&error),
        }
    }

    /// Decode exact biome IDs from grayscale or indexed PNG data.
    #[func]
    fn load_biome_png_bytes(&mut self, bytes: PackedByteArray, valid_ids: PackedByteArray) -> bool {
        match decode_biome_png(bytes.as_slice()) {
            Ok(raster) => {
                let mut allowed = [false; 256];
                for id in valid_ids.as_slice() {
                    allowed[*id as usize] = true;
                }
                if let Some(id) = raster.samples.iter().find(|id| !allowed[**id as usize]) {
                    return self.fail(&format!(
                        "biome layer contains an ID absent from map_config.json: {id}"
                    ));
                }
                self.biome_ids = Some(raster);
                self.last_error = GString::new();
                true
            }
            Err(error) => self.fail(&error),
        }
    }

    /// Test/editor bridge for supplying an already-generated elevation buffer.
    #[func]
    fn set_elevation_samples(
        &mut self,
        width: i32,
        height: i32,
        samples_m: PackedFloat32Array,
    ) -> bool {
        if width < 2 || height < 2 || samples_m.len() != width as usize * height as usize {
            return self.fail("elevation dimensions do not match the supplied sample count");
        }
        let values = samples_m.as_slice().to_vec();
        if values.iter().any(|v| !v.is_finite()) {
            return self.fail("elevation samples must be finite");
        }
        self.elevation = Some(Raster {
            width: width as usize,
            height: height as usize,
            samples: values,
        });
        self.last_error = GString::new();
        true
    }

    /// Test/editor bridge for supplying an already-generated biome ID buffer.
    #[func]
    fn set_biome_ids(&mut self, width: i32, height: i32, samples: PackedByteArray) -> bool {
        if width < 2 || height < 2 || samples.len() != width as usize * height as usize {
            return self.fail("biome dimensions do not match the supplied sample count");
        }
        self.biome_ids = Some(Raster {
            width: width as usize,
            height: height as usize,
            samples: samples.as_slice().to_vec(),
        });
        self.last_error = GString::new();
        true
    }

    #[func]
    fn elevation_width(&self) -> i32 {
        self.elevation.as_ref().map_or(0, |r| r.width as i32)
    }
    #[func]
    fn elevation_height(&self) -> i32 {
        self.elevation.as_ref().map_or(0, |r| r.height as i32)
    }
    #[func]
    fn biome_width(&self) -> i32 {
        self.biome_ids.as_ref().map_or(0, |r| r.width as i32)
    }
    #[func]
    fn biome_height(&self) -> i32 {
        self.biome_ids.as_ref().map_or(0, |r| r.height as i32)
    }
    #[func]
    fn elevation_samples_m(&self) -> PackedFloat32Array {
        self.elevation
            .as_ref()
            .map_or_else(PackedFloat32Array::new, |r| {
                PackedFloat32Array::from(r.samples.as_slice())
            })
    }
    #[func]
    fn biome_samples(&self) -> PackedByteArray {
        self.biome_ids
            .as_ref()
            .map_or_else(PackedByteArray::new, |r| {
                PackedByteArray::from(r.samples.as_slice())
            })
    }
    #[func]
    fn error_message(&self) -> GString {
        self.last_error.clone()
    }
    #[func]
    fn clear(&mut self) {
        self.elevation = None;
        self.biome_ids = None;
        self.last_error = GString::new();
    }

    #[func]
    fn sample_elevation(&self, theta: f64, z_m: f64, cylinder_length_m: f64) -> f64 {
        let Some(raster) = &self.elevation else {
            return 0.0;
        };
        match sample_elevation(raster, theta, z_m, cylinder_length_m) {
            Ok(value) => value as f64,
            Err(error) => {
                godot_error!("{error}");
                0.0
            }
        }
    }

    #[func]
    fn sample_biome_id(&self, theta: f64, z_m: f64, cylinder_length_m: f64) -> i32 {
        let Some(raster) = &self.biome_ids else {
            return -1;
        };
        match sample_biome(raster, theta, z_m, cylinder_length_m) {
            Ok(value) => value as i32,
            Err(error) => {
                godot_error!("{error}");
                -1
            }
        }
    }

    fn fail(&mut self, message: &str) -> bool {
        self.last_error = GString::from(message);
        false
    }
}

fn sample_elevation(
    raster: &Raster<f32>,
    theta: f64,
    z_m: f64,
    length_m: f64,
) -> Result<f32, String> {
    validate_query(theta, z_m, length_m)?;
    let u = theta.rem_euclid(std::f64::consts::TAU) / std::f64::consts::TAU;
    let v = (z_m / length_m + 0.5).clamp(0.0, 1.0);
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

fn sample_biome(raster: &Raster<u8>, theta: f64, z_m: f64, length_m: f64) -> Result<u8, String> {
    validate_query(theta, z_m, length_m)?;
    let u = theta.rem_euclid(std::f64::consts::TAU) / std::f64::consts::TAU;
    let v = (z_m / length_m + 0.5).clamp(0.0, 1.0);
    let x = ((u * raster.width as f64).round() as usize) % raster.width;
    let y = ((v * (raster.height - 1) as f64).round() as usize).min(raster.height - 1);
    Ok(raster.samples[y * raster.width + x])
}

fn validate_query(theta: f64, z_m: f64, length_m: f64) -> Result<(), String> {
    if !theta.is_finite() || !z_m.is_finite() || !length_m.is_finite() || length_m <= 0.0 {
        return Err(
            "terrain query coordinates and cylinder length must be finite; length must be positive"
                .into(),
        );
    }
    Ok(())
}

fn lerp(a: f32, b: f32, t: f32) -> f32 {
    a + (b - a) * t
}
