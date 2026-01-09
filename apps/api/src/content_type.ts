export const normalizeFileExtension = (raw: string | null) => {
  if (!raw) return null;
  let value = raw.trim().toLowerCase();
  if (!value) return null;
  if (value.startsWith(".")) {
    value = value.slice(1);
  }
  if (!value) return null;
  if (!/^[a-z0-9][a-z0-9+.-]{0,31}$/.test(value)) return null;
  return `.${value}`;
};
