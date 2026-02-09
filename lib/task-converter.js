/**
 * Convert Spec-Kit task format to coordinator JSON format
 */

function convertToCoordinatorTask(specKitTask, sequenceNumber) {
  // Convert to zero-padded ID (1 -> "001", 42 -> "042")
  const id = String(sequenceNumber).padStart(3, '0');

  // Determine type from user story or default to implementation
  const type = 'implementation';

  // Parallel tasks own files (exclusive), non-parallel tasks touch files (shared)
  const owns = specKitTask.parallel ? specKitTask.files : [];
  const touches = specKitTask.parallel ? [] : specKitTask.files;

  return {
    id,
    type,
    status: 'pending',
    description: specKitTask.description,
    acceptanceCriteria: [],
    owns,
    touches,
    blockedBy: [],
    claimedBy: null,
    history: [],
  };
}

/**
 * Build dependency graph by analyzing file ownership/usage
 * Tasks that touch files owned/touched by earlier tasks are blocked
 *
 * @param {Array} tasks - Array of coordinator tasks with owns/touches
 * @returns {Array} Same tasks with blockedBy populated
 */
function buildDependencyGraph(tasks) {
  // Clone tasks to avoid mutating input
  const result = tasks.map((task) => ({ ...task }));

  // Build file ownership map: file -> array of task IDs that own/touch it
  const fileOwners = new Map();

  for (const task of result) {
    // Track all files this task interacts with
    const allFiles = [...task.owns, ...task.touches];

    for (const file of allFiles) {
      if (!fileOwners.has(file)) {
        fileOwners.set(file, []);
      }
      fileOwners.get(file).push(task.id);
    }
  }

  // For each task, find dependencies based on file conflicts
  for (const task of result) {
    const blockers = new Set();
    const allFiles = [...task.owns, ...task.touches];

    for (const file of allFiles) {
      const owners = fileOwners.get(file);
      if (!owners) continue;

      // Find all tasks that touched this file before current task
      for (const ownerId of owners) {
        // Only block on earlier tasks (lower IDs)
        if (ownerId < task.id) {
          blockers.add(ownerId);
        }
      }
    }

    // Update blockedBy array
    task.blockedBy = Array.from(blockers).sort();
  }

  return result;
}

module.exports = { convertToCoordinatorTask, buildDependencyGraph };
