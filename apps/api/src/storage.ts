export type TokenRecord = { storageId: string; path: string };

export const tokenToStorage = new Map<string, TokenRecord>();
