import fs from 'node:fs';
import path from 'node:path';

function getArg(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index >= 0 ? process.argv[index + 1] : null;
}

const title = getArg('title');
const source = getArg('source');
const output = getArg('output');

if (!title || !source || !output) {
  console.error('Usage: node generate-flat-tfvars-docs.mjs --title <title> --source <tfvars> --output <md>');
  process.exit(1);
}

function countDelta(line) {
  let delta = 0;
  let inString = false;
  let escaped = false;

  for (const char of line) {
    if (escaped) {
      escaped = false;
      continue;
    }
    if (char === '\\') {
      escaped = true;
      continue;
    }
    if (char === '"') {
      inString = !inString;
      continue;
    }
    if (inString) {
      continue;
    }
    if (char === '{' || char === '[') {
      delta += 1;
    } else if (char === '}' || char === ']') {
      delta -= 1;
    }
  }

  return delta;
}

function cleanCommentLine(line) {
  return line.replace(/^\s*#\s?/, '').trimEnd();
}

function normalizeSectionName(text) {
  const trimmed = text.trim();
  if (!trimmed) {
    return null;
  }
  if (/^[=\-#\s]+$/.test(trimmed)) {
    return null;
  }
  if (trimmed.includes('=') || trimmed.startsWith('-')) {
    return null;
  }
  return trimmed;
}

function parseTfvars(raw) {
  const lines = raw.split('\n');
  const items = [];
  let currentSection = 'General';
  let pendingComments = [];

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const trimmed = line.trim();
    const uncommented = trimmed.startsWith('#')
      ? line.replace(/^\s*#\s?/, '')
      : line;
    const assignmentMatch = uncommented.match(/^([a-zA-Z0-9_]+)\s*=/);

    if (assignmentMatch) {
      const name = assignmentMatch[1];
      const exampleLines = [uncommented];
      let balance = countDelta(uncommented);
      let j = i + 1;

      while (j < lines.length && balance > 0) {
        const nextLine = lines[j].replace(/^\s*#\s?/, '');
        exampleLines.push(nextLine);
        balance += countDelta(nextLine);
        j += 1;
      }

      const inlineComment =
        uncommented.includes('#') ? uncommented.slice(uncommented.indexOf('#') + 1).trim() : null;
      const comments = pendingComments
        .map(cleanCommentLine)
        .map((value) => value.trim())
        .filter(Boolean)
        .filter((value) => !/^[=\-#\s]+$/.test(value));

      items.push({
        section: currentSection,
        name,
        comments,
        inlineComment,
        example: exampleLines.join('\n').trimEnd(),
      });

      i = j - 1;
      pendingComments = [];
      continue;
    }

    if (trimmed.startsWith('#')) {
      const cleaned = cleanCommentLine(line);
      const sectionName = normalizeSectionName(cleaned);
      if (sectionName) {
        currentSection = sectionName;
        pendingComments = [];
        continue;
      }
      pendingComments.push(line);
      continue;
    }

    if (trimmed === '') {
      pendingComments = [];
      continue;
    }

    pendingComments = [];
  }

  return items;
}

function descriptionFor(item) {
  if (item.comments.length > 0 && item.inlineComment) {
    return `${item.comments.join('\n')}\n${item.inlineComment}`;
  }
  if (item.comments.length > 0) {
    return item.comments.join('\n');
  }
  if (item.inlineComment) {
    return item.inlineComment;
  }
  return '_No inline description in `terraform.tfvars`._';
}

const sourcePath = path.resolve(process.cwd(), source);
const outputPath = path.resolve(process.cwd(), output);
const raw = fs.readFileSync(sourcePath, 'utf8');
const items = Array.from(
  parseTfvars(raw)
    .reduce((map, item) => {
      map.set(`${item.section}::${item.name}`, item);
      return map;
    }, new Map())
    .values(),
);
const grouped = new Map();

for (const item of items) {
  if (!grouped.has(item.section)) {
    grouped.set(item.section, []);
  }
  grouped.get(item.section).push(item);
}

const lines = [
  '---',
  'sidebar_position: 2',
  '---',
  '',
  '# Generated Configuration Reference',
  '',
  `This page is generated from \`${source.replace(/^\.\//, '')}\`.`,
  '',
  `Generation date: ${new Date().toISOString().slice(0, 10)}`,
  '',
  '## tfvars catalog',
  '',
];

for (const [section, sectionItems] of grouped) {
  lines.push(`## ${section}`);
  lines.push('');
  for (const item of sectionItems) {
    lines.push(`### \`${item.name}\``);
    lines.push('');
    lines.push(descriptionFor(item));
    lines.push('');
    lines.push('Example from `terraform.tfvars`:');
    lines.push('');
    lines.push('```hcl');
    lines.push(item.example);
    lines.push('```');
    lines.push('');
  }
}

lines.push('## Regeneration');
lines.push('');
lines.push('Run from `website/` with:');
lines.push('');
lines.push('```bash');
lines.push(`node ./scripts/generate-flat-tfvars-docs.mjs --title "${title}" --source "${source}" --output "${output}"`);
lines.push('```');
lines.push('');

fs.mkdirSync(path.dirname(outputPath), {recursive: true});
fs.writeFileSync(outputPath, `${lines.join('\n')}\n`);
console.log(`Wrote ${path.relative(process.cwd(), outputPath)}`);
