// Read common image dimensions without fetching outside the publication.
// A browser decoder handles additional formats when the platform supports them.
export async function imageDimensions(bytes, type) {
    const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
    const valid = (width, height) => Number.isFinite(width) && Number.isFinite(height)
        && width > 0 && height > 0 && width <= 100000 && height <= 100000
        ? {width, height} : null
    if (type === 'image/png' && bytes.length >= 24)
        return valid(view.getUint32(16), view.getUint32(20))
    if (type === 'image/gif' && bytes.length >= 10)
        return valid(view.getUint16(6, true), view.getUint16(8, true))
    if (type === 'image/jpeg') {
        let i = 2
        while (i + 9 < bytes.length) {
            if (bytes[i++] !== 0xff) break
            while (bytes[i] === 0xff) i++
            if (i >= bytes.length) break
            const marker = bytes[i++]
            if (marker === 0xd9 || marker === 0xda) break
            if (marker === 0x01 || (marker >= 0xd0 && marker <= 0xd7)) continue
            if (i + 2 > bytes.length) break
            const length = view.getUint16(i)
            if (length < 2 || i + length > bytes.length) break
            if (length >= 8 && [0xc0,0xc1,0xc2,0xc3,0xc5,0xc6,0xc7,0xc9,0xca,0xcb,0xcd,0xce,0xcf].includes(marker))
                return valid(view.getUint16(i + 5), view.getUint16(i + 3))
            i += length
        }
    }
    if (type === 'image/svg+xml') {
        const svg = new DOMParser().parseFromString(new TextDecoder().decode(bytes), type).documentElement
        const box = svg?.getAttribute('viewBox')?.trim().split(/[\s,]+/).map(Number)
        if (box?.length === 4) return valid(box[2], box[3])
        const width = svg?.getAttribute('width'), height = svg?.getAttribute('height')
        if (width && height && !width.includes('%') && !height.includes('%'))
            return valid(parseFloat(width), parseFloat(height))
    }
    if (typeof createImageBitmap === 'function') {
        let image
        try {
            image = await createImageBitmap(new Blob([bytes], {type}))
            return valid(image.width, image.height)
        } catch { /* Preserve the resource; the caller records missing viewport. */ }
        finally { image?.close() }
    }
    return null
}
