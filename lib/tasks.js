const fs = require('node:fs');
const path = require('node:path');

function listTasks(tasksDir) {
  if (!fs.existsSync(tasksDir)) return [];
  return fs
    .readdirSync(tasksDir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(fs.readFileSync(path.join(tasksDir, f), 'utf8')));
}

const DONE_STATUSES = new Set(['done', 'approved']);

function isBlocked(task, allTasks) {
  if (!task.blockedBy || task.blockedBy.length === 0) return false;
  return task.blockedBy.some((blockerId) => {
    const blocker = allTasks.find((t) => t.id === blockerId);
    return !blocker || !DONE_STATUSES.has(blocker.status);
  });
}

function findClaimable(tasks, capabilities, taskTypes, allTasks) {
  return tasks
    .filter(
      (t) => t.status === 'pending' && capabilities.includes(t.type) && !isBlocked(t, allTasks),
    )
    .sort((a, b) => (taskTypes[b.type]?.priority ?? 0) - (taskTypes[a.type]?.priority ?? 0));
}

function claimTask(taskFile, agentId) {
  const task = JSON.parse(fs.readFileSync(taskFile, 'utf8'));
  if (task.status !== 'pending') {
    throw new Error(`Task ${task.id} is not pending (status: ${task.status})`);
  }
  task.status = 'claimed';
  task.claimedBy = agentId;
  task.history = task.history || [];
  task.history.push({
    status: 'claimed',
    agent: agentId,
    timestamp: new Date().toISOString(),
  });
  fs.writeFileSync(taskFile, JSON.stringify(task, null, 2) + '\n');
  return task;
}

function updateTask(taskFile, newStatus, agentId) {
  const task = JSON.parse(fs.readFileSync(taskFile, 'utf8'));
  task.status = newStatus;
  task.history = task.history || [];
  task.history.push({
    status: newStatus,
    agent: agentId,
    timestamp: new Date().toISOString(),
  });
  fs.writeFileSync(taskFile, JSON.stringify(task, null, 2) + '\n');
  return task;
}

module.exports = { listTasks, findClaimable, claimTask, updateTask };
