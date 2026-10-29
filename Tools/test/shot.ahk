; a saved 24-bit .bmp with the same GetColor(x, y) a FindText screenshot has
class Shot {
    __New(file) {
        b := FileRead(file, "RAW")
        this.off := NumGet(b, 10, "UInt"), this.w := NumGet(b, 18, "Int"), this.h := NumGet(b, 22, "Int")
        this.stride := (this.w * 3 + 3) & ~3, this.b := b
    }
    GetColor(x, y, *) {
        if x < 0 || y < 0 || x >= this.w || y >= this.h
            return 0
        p := this.off + (this.h - 1 - y) * this.stride + x * 3
        return (NumGet(this.b, p + 2, "UChar") << 16) | (NumGet(this.b, p + 1, "UChar") << 8) | NumGet(this.b, p, "UChar")
    }
}

