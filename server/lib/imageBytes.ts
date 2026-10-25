export const MAX_IMAGE_BYTES = 8 * 1024 * 1024;

const SIGNATURES = {
  "image/png": [[0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]]],
  "image/jpeg": [[0, [0xff, 0xd8, 0xff]]],
  "image/webp": [
    [0, [0x52, 0x49, 0x46, 0x46]],
    [8, [0x57, 0x45, 0x42, 0x50]],
  ],
} as const;

export function hasExpectedMagicBytes(bytes: Uint8Array, type: keyof typeof SIGNATURES): boolean {
  return SIGNATURES[type].every(([offset, signature]) =>
    signature.every((byte, index) => bytes[offset + index] === byte),
  );
}
