use std::fs;
use std::io::Write;

fn main() {
    // Read input file
    match fs::read_to_string("/input.txt") {
        Ok(content) => {
            // Write transformed output
            let output = format!("processed: {}", content.trim());
            let mut f = fs::File::create("/output.txt").expect("create output");
            f.write_all(output.as_bytes()).expect("write output");
            println!("{}", output);
        }
        Err(e) => {
            eprintln!("error reading /input.txt: {}", e);
            std::process::exit(1);
        }
    }
}
