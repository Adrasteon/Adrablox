use std::env;
use std::fs::File;
use std::io::BufReader;

use rbx_dom_weak::{types::Ref, WeakDom};
use rbx_types::Variant;

fn print_tree(dom: &WeakDom, referent: Ref, depth: usize) {
    if let Some(instance) = dom.get_by_ref(referent) {
        let indent = "  ".repeat(depth);
        println!("{indent}- {} ({})", instance.name, instance.class);
        for child in instance.children() {
            print_tree(dom, *child, depth + 1);
        }
    }
}

fn inspect_rbxm(in_path: &str) -> anyhow::Result<()> {
    let f = File::open(in_path)?;
    let reader = BufReader::new(f);
    let tree = rbx_binary::from_reader(reader)?;

    let top_level_count = tree.root().children().len();
    println!("top_level_instances={top_level_count}");
    println!("hierarchy:");
    for child in tree.root().children() {
        print_tree(&tree, *child, 0);
    }

    let mut scripts_total = 0usize;
    let mut scripts_with_source = 0usize;
    let mut scripts_without_source = 0usize;

    for instance in tree.descendants() {
        let class = instance.class.as_str();
        if class == "Script" || class == "LocalScript" || class == "ModuleScript" {
            scripts_total += 1;
            let source_len = instance
                .properties
                .iter()
                .find_map(|(name, value)| {
                    if name.as_str() == "Source" {
                        match value {
                            Variant::String(source) => Some(source.len()),
                            _ => Some(0usize),
                        }
                    } else {
                        None
                    }
                })
                .unwrap_or(0usize);

            if source_len > 0 {
                scripts_with_source += 1;
            } else {
                scripts_without_source += 1;
            }

            println!(
                "{class} {} source_len={source_len}",
                instance.name
            );
        }
    }

    println!(
        "summary: scripts_total={scripts_total} scripts_with_source={scripts_with_source} scripts_without_source={scripts_without_source}"
    );

    Ok(())
}

fn main() -> anyhow::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() == 3 && args[1] == "--inspect-rbxm" {
        return inspect_rbxm(&args[2]);
    }

    if args.len() != 3 {
        eprintln!("usage: rbx_write <in.rbxmx> <out.rbxm>");
        eprintln!("   or: rbx_write --inspect-rbxm <in.rbxm>");
        std::process::exit(2);
    }
    let in_path = &args[1];
    let out_path = &args[2];

    let f = File::open(in_path)?;
    let mut reader = BufReader::new(f);

    // Parse XML to DOM with default options
    let opts = rbx_xml::DecodeOptions::default();
    let tree = rbx_xml::from_reader(&mut reader, opts)?;

    // Write binary (.rbxm) from the actual top-level instances (children of
    // the WeakDom pseudo-root). Serializing the pseudo-root itself can produce
    // artifacts that Roblox Studio treats as invalid or empty.
    let root_children: Vec<_> = tree.root().children().to_vec();
    if root_children.is_empty() {
        anyhow::bail!("Input .rbxmx has no top-level instances to serialize");
    }

    let mut buf: Vec<u8> = Vec::new();
    rbx_binary::to_writer(&mut buf, &tree, &root_children)?;
    std::fs::write(out_path, &buf)?;

    println!("Wrote {}", out_path);
    Ok(())
}
