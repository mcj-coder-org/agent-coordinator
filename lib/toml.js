function parseTOML(input) {
  const result = {};
  let currentSection = result;
  const lines = input.split('\n');

  for (const raw of lines) {
    const line = raw.trim();
    if (!line || line.startsWith('#')) continue;

    // Table header: [section.subsection]
    const tableMatch = line.match(/^\[([^\]]+)\]$/);
    if (tableMatch) {
      const keys = tableMatch[1].split('.');
      currentSection = result;
      for (const key of keys) {
        if (!currentSection[key]) currentSection[key] = {};
        currentSection = currentSection[key];
      }
      continue;
    }

    // Key-value pair
    const kvMatch = line.match(/^([a-zA-Z0-9_-]+)\s*=\s*(.+)$/);
    if (kvMatch) {
      const key = kvMatch[1];
      const rawValue = kvMatch[2].trim();
      currentSection[key] = parseValue(rawValue);
    }
  }

  return result;
}

function parseValue(raw) {
  // String
  if (raw.startsWith('"') && raw.endsWith('"')) {
    return raw.slice(1, -1);
  }
  // Number
  if (/^-?\d+(\.\d+)?$/.test(raw)) {
    return Number(raw);
  }
  // Boolean
  if (raw === 'true') return true;
  if (raw === 'false') return false;
  // Array
  if (raw.startsWith('[') && raw.endsWith(']')) {
    const inner = raw.slice(1, -1).trim();
    if (!inner) return [];
    return inner.split(',').map((v) => parseValue(v.trim()));
  }
  return raw;
}

module.exports = { parseTOML };
