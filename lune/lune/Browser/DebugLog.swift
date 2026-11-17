#if DEBUG
func diagnostic(_ message: String) {
    print("lune:", message)
}
#else
func diagnostic(_ message: String) {}
#endif
