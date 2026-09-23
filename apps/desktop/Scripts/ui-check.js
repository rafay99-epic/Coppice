function run(argv) {
  const processName = argv[0] || "Coppice Dev";
  const events = Application("System Events");
  const app = events.processes().find((candidate) => candidate.displayedName() === processName || candidate.name() === processName);
  if (!app) throw new Error(`${processName} is not running`);

  const failures = [];
  const check = (label, passed) => { if (!passed) failures.push(label); };
  const texts = [];
  const values = [];

  function walk(element, depth) {
    if (depth > 12) return;
    let role = "";
    try { role = element.role(); } catch (error) { return; }
    if (role === "AXOutline" && depth > 6) return;
    if (role === "AXStaticText") { try { texts.push(String(element.name() || element.value() || "")); } catch (error) {} }
    try { const value = element.attributes["AXValue"].value(); if (value) values.push(String(value)); } catch (error) {}
    let children = [];
    try { children = element.uiElements(); } catch (error) {}
    children.forEach((child) => walk(child, depth + 1));
  }

  check("menu bar item present", app.menuBars[1].menuBarItems.length > 0);
  const windows = app.windows();
  if (windows.length) {
    walk(windows[0], 0);
    const summaryIndex = texts.findIndex((text) => /^\d+ worktrees · /.test(text));
    const onboarding = texts.some((text) => text.startsWith("Your agents left"));
    check("worktree summary shown", onboarding || summaryIndex >= 0);
    check("scope heading above the summary", onboarding || (summaryIndex > 0 && texts[summaryIndex - 1].length > 0));
    check("sidebar counts exposed to VoiceOver", onboarding || values.some((value) => /^\d+ worktrees$/.test(value)));
  }

  const summary = `${processName}: ${windows.length} window(s), ${texts.length} texts, ${values.length} values`;
  if (failures.length) throw new Error(`${summary}\nfailed: ${failures.join(", ")}`);
  return `${summary}\nall checks passed`;
}
