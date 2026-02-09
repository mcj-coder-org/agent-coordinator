const fs = require('node:fs');
const path = require('node:path');

function listTasks(tasksDir) {
  if (!fs.existsSync(tasksDir)) return [];
  return fs
    .readdirSync(tasksDir)
    .filter((f) => f.endsWith('.json'))
    .map((f) => JSON.parse(fs.readFileSync(path.join(tasksDir, f), 'utf8')));
}

const DONE_STATUSES = new Set(['complete', 'done', 'approved']);

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

function reclaimTasks(tasksDir, agentId) {
  const tasks = listTasks(tasksDir);
  const reclaimed = [];

  for (const task of tasks) {
    if (task.status === 'claimed' && task.claimedBy === agentId) {
      const taskFile = path.join(tasksDir, `${task.id}.json`);
      task.status = 'pending';
      task.claimedBy = null;
      task.history = task.history || [];
      task.history.push({
        status: 'pending',
        agent: agentId,
        timestamp: new Date().toISOString(),
        note: 'reclaimed on startup',
      });
      fs.writeFileSync(taskFile, JSON.stringify(task, null, 2) + '\n');
      reclaimed.push(task);
    }
  }

  return reclaimed;
}

module.exports = { listTasks, findClaimable, claimTask, updateTask, reclaimTasks };

if (require.main === module) {
  const [, , command, ...args] = process.argv;

  if (command === 'claim') {
    const [tasksDir, configFile, agentId, ...capabilities] = args;
    const { parseTOML } = require('./toml.js');
    let config;
    if (configFile.endsWith('.toml')) {
      config = parseTOML(fs.readFileSync(configFile, 'utf8'));
    } else {
      config = JSON.parse(fs.readFileSync(configFile, 'utf8'));
    }
    const taskTypes = config['task-types'] || {};
    const tasks = listTasks(tasksDir);
    const claimable = findClaimable(tasks, capabilities, taskTypes, tasks);
    if (claimable.length === 0) {
      process.exit(0);
    }
    const target = claimable[0];
    const taskFile = path.join(tasksDir, `${target.id}.json`);
    const claimed = claimTask(taskFile, agentId);
    const claudeMd = taskTypes[claimed.type]?.['claude-md'] || '';
    console.log(JSON.stringify({ taskId: claimed.id, taskType: claimed.type, claudeMd }));
  } else if (command === 'update') {
    const [taskFile, newStatus, agentId] = args;
    updateTask(taskFile, newStatus, agentId);
  } else if (command === 'reclaim') {
    const [tasksDir, agentId] = args;
    const reclaimed = reclaimTasks(tasksDir, agentId);
    if (reclaimed.length > 0) {
      console.log(
        `Reclaimed ${reclaimed.length} task(s): ${reclaimed.map((t) => t.id).join(', ')}`,
      );
    }
  } else {
    console.error(`Unknown command: ${command}`);
    process.exit(1);
  }
}
