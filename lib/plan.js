#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');
const { parseTasksMarkdown } = require('./speckit-parser.js');
const { convertToCoordinatorTask, buildDependencyGraph } = require('./task-converter.js');

function main() {
  const [, , tasksFile, outputDir] = process.argv;

  if (!tasksFile || !outputDir) {
    console.error('Usage: node plan.js <tasks.md> <output-dir>');
    process.exit(1);
  }

  if (!fs.existsSync(tasksFile)) {
    console.error(`Error: ${tasksFile} not found`);
    process.exit(1);
  }

  if (!fs.existsSync(outputDir)) {
    console.error(`Error: ${outputDir} not found`);
    process.exit(1);
  }

  // Read and parse tasks.md
  const markdown = fs.readFileSync(tasksFile, 'utf8');
  const specKitTasks = parseTasksMarkdown(markdown);

  if (specKitTasks.length === 0) {
    console.error('Error: No tasks found in tasks.md');
    process.exit(1);
  }

  // Convert to coordinator format
  const coordinatorTasks = specKitTasks.map((task, index) =>
    convertToCoordinatorTask(task, index + 1),
  );

  // Build dependency graph
  const tasksWithDeps = buildDependencyGraph(coordinatorTasks);

  // Write JSON files
  for (const task of tasksWithDeps) {
    const filename = path.join(outputDir, `${task.id}.json`);
    fs.writeFileSync(filename, JSON.stringify(task, null, 2) + '\n');
  }

  console.log(`Converted ${tasksWithDeps.length} tasks to ${outputDir}/`);
}

if (require.main === module) {
  main();
}

module.exports = { main };
