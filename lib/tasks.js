const fs = require('node:fs');
const path = require('node:path');

function listTasks(tasksDir) {
  if (!fs.existsSync(tasksDir)) return [];
  return fs
    .readdirSync(tasksDir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(fs.readFileSync(path.join(tasksDir, f), 'utf8')));
}

module.exports = { listTasks };
