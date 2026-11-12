import { expect, test } from "bun:test";
import { cssOutput, parseTokens, swiftName, swiftOutput } from "./build-tokens.ts";

const source = {
  color: { "card-border": { light: "#E6E6E9", dark: "#34343a" }, text: { light: "#000000D9", dark: "#FFFFFFD9" } },
  font: { "card-title": { size: 14, weight: "semibold" } },
  space: { "28": 28 },
  padding: { button: { x: 9, y: 4.5 } },
  shadow: { card: { opacity: 0.04, radius: 2, y: 1 } },
};

const parsed = () => {
  const tokens = parseTokens(source);
  if (!tokens.ok) throw new Error(tokens.error);
  return tokens.value;
};

test("a kebab name becomes lower camel case, and a space number gets the prefix s", () => {
  expect(swiftName("color", "card-border")).toBe("cardBorder");
  expect(swiftName("font", "heading-1")).toBe("heading1");
  expect(swiftName("space", "28")).toBe("s28");
  const swift = swiftOutput(parsed());
  expect(swift).toContain("static let cardBorder = SwiftUI.Color(light: 0xE6E6E9FF, dark: 0x34343AFF)");
  expect(swift).toContain("static let cardTitle = SwiftUI.Font.system(size: 14, weight: .semibold)");
  expect(swift).toContain("static let s28: CGFloat = 28");
});

test("an 8 digit hex keeps its alpha last in Swift and in CSS", () => {
  expect(swiftOutput(parsed())).toContain("static let text = SwiftUI.Color(light: 0x000000D9, dark: 0xFFFFFFD9)");
  expect(cssOutput(parsed())).toContain("  --text: #000000D9;");
});

test("the CSS has the light values in :root and the dark values in a media block", () => {
  const [light, dark] = cssOutput(parsed()).split("@media (prefers-color-scheme: dark)");
  expect(light).toContain("--card-border: #E6E6E9;");
  expect(light).toContain("--font-card-title-size: 14px;");
  expect(light).toContain("--font-card-title-weight: 600;");
  expect(light).toContain("--padding-button: 4.5px 9px;");
  expect(light).toContain("--shadow-card: 0 1px 2px rgb(0 0 0 / 0.04);");
  expect(dark).toContain("--card-border: #34343A;");
  expect(dark).not.toContain("--font-");
});

test("each break of the contract fails the build with its reason", () => {
  const failure = (tokens: unknown) => {
    const result = parseTokens(tokens);
    return result.ok ? undefined : result.error;
  };
  expect(failure({ colour: {} })).toContain("unknown group");
  expect(failure({ color: { canvas: { light: "#FFF", dark: "#000000" } } })).toContain("not a hex color");
  expect(failure({ color: { canvas: { light: "#FFFFFF" } } })).toContain("color.canvas.dark");
  expect(failure({ font: { body: { size: 13, weight: "heavy" } } })).toContain("is not one of regular, medium, semibold, bold");
  expect(failure({ radius: { cardRadius: 14 } })).toContain("kebab case");
  expect(failure({ space: { small: 2 } })).toContain("a space name is a number");
  expect(failure({ opacity: { tint: 2 } })).toContain("from 0 to 1");
});
