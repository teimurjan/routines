// Bun bundles a Markdown or text import as a string.
declare module "*.md" {
  const text: string;
  export default text;
}

declare module "*.txt" {
  const text: string;
  export default text;
}
