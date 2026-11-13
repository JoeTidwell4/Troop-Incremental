use std::fs;
fn main() {
    let mut failed = 0;
    for path in std::env::args().skip(1) {
        let code = fs::read_to_string(&path).expect("read");
        if let Err(errors) = full_moon::parse(&code) {
            failed += 1;
            for e in errors { println!("{}: {}", path, e); }
        }
    }
    println!("files with errors: {}", failed);
}
