import { expect, test } from "bun:test";
import { cleanOutgoing, hasSecret } from "./outgoing.ts";

const owners = ["AcmeInc"];

test("keeps links to known GitHub owners and removes other links", () => {
  expect(cleanOutgoing("See https://github.com/acmeinc/web/pull/1.", owners)).toContain("github.com/acmeinc/web/pull/1");
  expect(cleanOutgoing("Log in at https://evil.example/x now", owners)).toBe("Log in at [link removed] now");
  expect(cleanOutgoing("See https://github.com/attacker/x", owners)).toBe("See [link removed]");
  expect(cleanOutgoing("See https://github.com.evil.example/AcmeInc/x", owners)).toBe("See [link removed]");
  expect(cleanOutgoing("See www.evil.example/x", owners)).toBe("See [link removed]");
});

test("removes secrets", () => {
  const token = `ghp_${"a".repeat(36)}`;
  expect(hasSecret(token)).toBe(true);
  expect(hasSecret("no token here")).toBe(false);
  expect(cleanOutgoing(`token ${token}`, owners)).toBe("token [secret removed]");
});

test("hasSecret gives the same answer on repeated calls", () => {
  const token = `ghp_${"a".repeat(36)}`;
  expect([hasSecret(token), hasSecret(token)]).toEqual([true, true]);
});

test("stops pings in Slack and GitHub", () => {
  expect(cleanOutgoing("<!channel> look <@U123> <#C123>", owners)).toBe(" look  ");
  expect(cleanOutgoing("cc @alice", owners)).toBe("cc @​alice");
  expect(cleanOutgoing("mail a@b.co", owners)).toBe("mail a@b.co");
});

test("caps the length", () => {
  expect(cleanOutgoing("x".repeat(5000), owners)).toHaveLength(3000);
});
