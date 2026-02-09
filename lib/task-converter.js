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

module.exports = { convertToCoordinatorTask };
