// lamp_post.scad

module lamp_post() {
    // Pedestal
    cylinder(h=0.55, r1=0.45, r2=0.14, $fn=12);
    
    // Post
    translate([0, 0, 0.55])
    cylinder(h=4.2, r1=0.14, r2=0.09, $fn=12);
    
    // Arm
    translate([0, 0, 4.6])
    rotate([0, 90, 0])
    cylinder(h=0.95, r=0.04, $fn=12);
    
    // Lantern head
    translate([0.95, 0, 4.6 - 0.55])
    cylinder(h=0.55, r=0.24, $fn=6);
    
    // Cone cap
    translate([0.95, 0, 4.6])
    cylinder(h=0.22, r1=0.34, r2=0.06, $fn=6);
}

lamp_post();
