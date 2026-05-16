fn greeting(who: &str) -> String {
    format!("Hello, {} from Firefly Engineering!", who)
}

fn main() {
    println!("{}", greeting("world"));
    println!("This is a Rust binary built with Buck2 in our monorepo.");
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn greets_named_target() {
        assert_eq!(greeting("world"), "Hello, world from Firefly Engineering!");
    }

    #[test]
    fn greets_empty_target() {
        assert_eq!(greeting(""), "Hello,  from Firefly Engineering!");
    }
}
