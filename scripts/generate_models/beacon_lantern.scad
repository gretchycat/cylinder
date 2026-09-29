// beacon_lantern.scad

module beacon_lantern() {
    // Metal post
    cylinder(h=2.2, r1=0.25, r2=0.15, $fn=8);
    
    // Crystal housing
    translate([0, 0, 2.2 + 0.32])
    sphere(r=0.32, $fn=16);
    
    // Cage/frame
    translate([0, 0, 2.2 + 0.32])
    rotate_extrude($fn=16)
    translate([0.35, 0, 0])
    circle(r=0.03, $fn=8);
}

beacon_lantern();
