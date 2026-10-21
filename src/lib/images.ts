const SUPPORTED_COVER_TYPES = ["image/jpeg", "image/png", "image/webp"];
export const MAX_COVER_BYTES = 10 * 1024 * 1024;

export function validateGatheringCover(file: File) {
  if (!SUPPORTED_COVER_TYPES.includes(file.type))
    throw new Error("Choose a JPG, PNG, or WebP image.");
  if (file.size > MAX_COVER_BYTES)
    throw new Error("The cover image must be 10 MB or smaller.");
}

export async function optimizeGatheringCover(file: File): Promise<Blob> {
  validateGatheringCover(file);
  const bitmap = await createImageBitmap(file);
  const targetWidth = 1200;
  const targetHeight = 630;
  const sourceRatio = bitmap.width / bitmap.height;
  const targetRatio = targetWidth / targetHeight;
  const sourceWidth =
    sourceRatio > targetRatio ? bitmap.height * targetRatio : bitmap.width;
  const sourceHeight =
    sourceRatio > targetRatio ? bitmap.height : bitmap.width / targetRatio;
  const sourceX = (bitmap.width - sourceWidth) / 2;
  const sourceY = (bitmap.height - sourceHeight) / 2;
  const canvas = document.createElement("canvas");
  canvas.width = targetWidth;
  canvas.height = targetHeight;
  const context = canvas.getContext("2d");
  if (!context)
    throw new Error("This browser could not prepare the cover image.");
  context.drawImage(
    bitmap,
    sourceX,
    sourceY,
    sourceWidth,
    sourceHeight,
    0,
    0,
    targetWidth,
    targetHeight,
  );
  bitmap.close();
  return await new Promise<Blob>((resolve, reject) =>
    canvas.toBlob(
      (blob) =>
        blob
          ? resolve(blob)
          : reject(
              new Error("This browser could not prepare the cover image."),
            ),
      "image/webp",
      0.84,
    ),
  );
}

export function publicStoragePath(publicUrl?: string) {
  if (!publicUrl) return null;
  const marker = "/storage/v1/object/public/circle-public-media/";
  const index = publicUrl.indexOf(marker);
  return index === -1
    ? null
    : decodeURIComponent(publicUrl.slice(index + marker.length));
}
