/**
 * Parse Spec-Kit tasks.md markdown format into JSON.
 *
 * Supports Spec-Kit markdown task format with optional markers:
 * - Task IDs: T001, T002, etc.
 * - Parallel marker: [P]
 * - User story labels: [US1], [US2], etc.
 * - Completed tasks marked with [x] are ignored
 *
 * File paths are automatically extracted from task descriptions,
 * matching both root-level files (README.md) and nested paths
 * (src/model.py). Supports hyphens, underscores, and dots in names.
 *
 * @param {string} markdown - The markdown content to parse
 * @returns {Array<{
 *   taskId: string,
 *   description: string,
 *   parallel: boolean,
 *   userStory: string|null,
 *   files: string[]
 * }>} Array of parsed task objects
 *
 * @example
 * const markdown = `
 * - [ ] T001 Update README.md with install steps
 * - [ ] T002 [P] [US1] Add auth in src/auth.py
 * - [x] T003 Completed task (ignored)
 * `;
 * const tasks = parseTasksMarkdown(markdown);
 * // [
 * //   { taskId: 'T001', description: 'Update README.md...', parallel: false, userStory: null, files: ['README.md'] },
 * //   { taskId: 'T002', description: 'Add auth...', parallel: true, userStory: 'US1', files: ['src/auth.py'] }
 * // ]
 */
function parseTasksMarkdown(markdown) {
  if (!markdown || markdown.trim() === '') {
    return [];
  }

  const lines = markdown.split('\n');
  const tasks = [];

  // Regex to match uncompleted tasks: - [ ] T001 [P] [US1] Description
  const taskRegex = /^- \[ \] (T\d+)\s+(.*)/;
  const parallelRegex = /\[P\]/;
  const userStoryRegex = /\[US(\d+)\]/;
  // Match both nested paths (src/file.py) and root-level files (README.md)
  const fileRegex = /\b[\w\-./]*\/?[\w\-./]+\.\w+\b/g;

  for (const line of lines) {
    const match = line.match(taskRegex);
    if (!match) continue;

    const taskId = match[1];
    let description = match[2].trim();

    // Extract markers
    const isParallel = parallelRegex.test(description);
    const userStoryMatch = description.match(userStoryRegex);
    const userStory = userStoryMatch ? `US${userStoryMatch[1]}` : null;

    // Remove markers from description
    description = description.replace(parallelRegex, '').replace(userStoryRegex, '').trim();

    // Extract file paths
    const files = description.match(fileRegex) || [];

    tasks.push({
      taskId,
      description,
      parallel: isParallel,
      userStory,
      files,
    });
  }

  return tasks;
}

module.exports = { parseTasksMarkdown };
