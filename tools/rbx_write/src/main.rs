use std::env;
use std::fs::File;
use std::io::{BufReader, BufWriter};

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() != 3 {
        eprintln!("usage: rbx_write <in.rbxmx> <out.rbxm>");
        std::process::exit(2);
    }
    let in_path = &args[1];
    let out_path = &args[2];

    let f = File::open(in_path)?;
    let mut reader = BufReader::new(f);

    // Parse XML to DOM with default options
    let opts = rbx_xml::DecodeOptions::default();
    let tree = rbx_xml::from_reader(&mut reader, opts)?;

    // Write binary (.rbxm)
    let out = File::create(out_path)?;
    let writer = BufWriter::new(out);
    rbx_binary::to_writer(writer, &tree, &[])?;

    println!("Wrote {}", out_path);
    Ok(())
}
