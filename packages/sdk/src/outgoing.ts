const SECRET_PATTERNS = [
  /\bgh[pousr]_[A-Za-z0-9]{36,}/g,
  /\bgithub_pat_\w{22,}/g,
  /\bxox[abeoprs]-[\w-]{10,}/g,
  /\bsk-ant-[\w-]{20,}/g,
  /\bnpm_[A-Za-z0-9]{36,}/g,
  /\bAKIA[0-9A-Z]{16}\b/g,
  /\bAIza[\w-]{35}/g,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/g,
];

const MAX_CHARS = 3000;

export const hasSecret = (text: string) => SECRET_PATTERNS.some((pattern) => text.search(pattern) !== -1);

const redactSecrets = (text: string) => SECRET_PATTERNS.reduce((clean, pattern) => clean.replace(pattern, "[secret removed]"), text);

const isOwnedGithubUrl = (url: string, owners: string[]) => {
  const parsed = URL.parse(url);
  const owner = parsed?.pathname.split("/")[1]?.toLowerCase();
  return parsed?.protocol === "https:" && parsed.hostname === "github.com" && owners.some((known) => known.toLowerCase() === owner);
};

const removeForeignLinks = (text: string, owners: string[]) =>
  text.replace(/\b(?:https?:\/\/|www\.)[^\s)>\]]+/gi, (url) => (isOwnedGithubUrl(url, owners) ? url : "[link removed]"));

// A zero-width space stops the ping and keeps the text readable.
const removeMentions = (text: string) =>
  text
    .replace(/<![^>]*>/g, "")
    .replace(/<[@#][^>]*>/g, "")
    .replace(/(^|[\s(])@(?=[\w-])/gm, "$1@​");

// Text from an agent goes out under my name, so it cannot carry secrets, foreign links or pings.
export const cleanOutgoing = (text: string, owners: string[]) =>
  removeMentions(removeForeignLinks(redactSecrets(text), owners)).slice(0, MAX_CHARS);
