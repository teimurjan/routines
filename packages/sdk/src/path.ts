// POSIX path helpers, because JavaScriptCore has no `node:path`.
const normalize = (path: string) => {
  const absolute = path.startsWith("/");
  const parts: string[] = [];
  for (const part of path.split("/")) {
    if (part === "" || part === ".") continue;
    if (part === ".." && parts.length > 0 && parts.at(-1) !== "..") parts.pop();
    else if (part !== ".." || !absolute) parts.push(part);
  }
  const joined = parts.join("/");
  return absolute ? `/${joined}` : joined || ".";
};

export const join = (...parts: string[]) => normalize(parts.filter((part) => part !== "").join("/"));

export const dirname = (path: string) => {
  const normal = normalize(path);
  const slash = normal.lastIndexOf("/");
  if (slash === -1) return ".";
  return slash === 0 ? "/" : normal.slice(0, slash);
};

export const basename = (path: string) => normalize(path).split("/").at(-1) ?? "";
