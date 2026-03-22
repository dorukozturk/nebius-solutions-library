import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(process.cwd(), '..');
const tfvarsPath = path.join(repoRoot, 'k8s-training', 'terraform.tfvars');
const localsPath = path.join(repoRoot, 'k8s-training', 'locals.tf');
const outputPath = path.join(
  repoRoot,
  'website',
  'docs',
  'k8s-training',
  'generated-configuration-reference.md',
);

function cleanCommentLine(line) {
  return line.replace(/^\s*#\s?/, '').trimEnd();
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

function sanitizeCommentBlock(lines) {
  const cleaned = [];
  let skipExampleBalance = 0;

  for (const rawLine of lines) {
    const line = cleanCommentLine(rawLine).trimEnd();
    const trimmed = line.trim();

    if (!trimmed) {
      continue;
    }

    if (/^[-#\s|=]+$/.test(trimmed)) {
      continue;
    }

    if (skipExampleBalance > 0) {
      skipExampleBalance += countDelta(trimmed);
      continue;
    }

    if (/^[a-z0-9_]+\s*=/.test(trimmed)) {
      skipExampleBalance = countDelta(trimmed);
      if (skipExampleBalance <= 0) {
        skipExampleBalance = 0;
      }
      continue;
    }

    if (/^[{}\[\],]+$/.test(trimmed)) {
      continue;
    }

    cleaned.push(line);
  }

  return cleaned;
}

function parseTfvars(raw) {
  const lines = raw.split('\n');
  const items = [];
  let pendingComments = [];
  let currentSection = 'General';

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const trimmed = line.trim();

    if (trimmed.startsWith('#')) {
      const cleaned = cleanCommentLine(line).trim();
      if (
        cleaned &&
        !cleaned.endsWith('.') &&
        !cleaned.includes('=') &&
        !cleaned.startsWith('-') &&
        cleaned.length < 40
      ) {
        currentSection = cleaned;
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

    const assignmentMatch = line.match(/^([a-zA-Z0-9_]+)\s*=/);
    if (!assignmentMatch) {
      pendingComments = [];
      continue;
    }

    const name = assignmentMatch[1];
    const exampleLines = [line];
    let balance = countDelta(line);
    let j = i + 1;

    while (j < lines.length && balance > 0) {
      exampleLines.push(lines[j]);
      balance += countDelta(lines[j]);
      j += 1;
    }

    items.push({
      section: currentSection,
      name,
      comments: sanitizeCommentBlock(pendingComments),
      inlineComment:
        line.includes('#') ? line.slice(line.indexOf('#') + 1).trim() : null,
      example: exampleLines.join('\n').trimEnd(),
    });

    i = j - 1;
    pendingComments = [];
  }

  return items;
}

function parseRegionDefaults(raw) {
  const defaults = [];
  const regionRegex =
    /^\s*([a-z0-9-]+)\s*=\s*\{([\s\S]*?)^\s*\}/gm;

  for (const match of raw.matchAll(regionRegex)) {
    const region = match[1];
    const body = match[2];

    if (region === 'default' || !body.includes('cpu_nodes_platform')) {
      continue;
    }

    defaults.push({
      region,
      cpuPlatform: body.match(/cpu_nodes_platform\s*=\s*"([^"]+)"/)?.[1] ?? 'n/a',
      cpuPreset: body.match(/cpu_nodes_preset\s*=\s*"([^"]+)"/)?.[1] ?? 'n/a',
      gpuPlatform: body.match(/gpu_nodes_platform\s*=\s*"([^"]+)"/)?.[1] ?? 'n/a',
      gpuPreset: body.match(/gpu_nodes_preset\s*=\s*"([^"]+)"/)?.[1] ?? 'n/a',
      infinibandFabric: body.match(/infiniband_fabric\s*=\s*"([^"]+)"/)?.[1] ?? 'n/a',
    });
  }

  return defaults;
}

function formatCommentBlock(comments, inlineComment, example) {
  const fallbackInline = example.split('\n')[0].includes('#')
    ? example.split('\n')[0].slice(example.split('\n')[0].indexOf('#') + 1).trim()
    : null;
  const effectiveInline = inlineComment ?? fallbackInline;

  if (comments.length === 0) {
    if (effectiveInline) {
      return effectiveInline;
    }

    return '_No inline description in `terraform.tfvars`._';
  }

  const body = comments.map((line) => line.trim()).join('\n');
  return effectiveInline ? `${body}\n${effectiveInline}` : body;
}

function buildMarkdown(items, defaults) {
  const generatedAt = new Date().toISOString().slice(0, 10);
  const grouped = new Map();

  for (const item of items) {
    if (!grouped.has(item.section)) {
      grouped.set(item.section, []);
    }
    grouped.get(item.section).push(item);
  }

  const lines = [
    '---',
    'sidebar_position: 4',
    '---',
    '',
    '# Generated Configuration Reference',
    '',
    'This page is generated from `k8s-training/terraform.tfvars` and the region defaults defined in `k8s-training/locals.tf`.',
    '',
    `Generation date: ${generatedAt}`,
    '',
    '## Region defaults',
    '',
  ];

  for (const item of defaults) {
    lines.push(`### \`${item.region}\``);
    lines.push('');
    lines.push(`- CPU: \`${item.cpuPlatform}\` / \`${item.cpuPreset}\``);
    lines.push(`- GPU: \`${item.gpuPlatform}\` / \`${item.gpuPreset}\``);
    lines.push(`- InfiniBand fabric: \`${item.infinibandFabric}\``);
    lines.push('');
  }

  lines.push('## tfvars catalog');
  lines.push('');

  for (const [section, sectionItems] of grouped) {
    lines.push(`## ${section}`);
    lines.push('');

    for (const item of sectionItems) {
      lines.push(`### \`${item.name}\``);
      lines.push('');
      lines.push(formatCommentBlock(item.comments, item.inlineComment, item.example));
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
  lines.push('Run this from `website/`:');
  lines.push('');
  lines.push('```bash');
  lines.push('npm run generate:k8s-training-docs');
  lines.push('```');
  lines.push('');

  return `${lines.join('\n')}\n`;
}

const tfvarsRaw = fs.readFileSync(tfvarsPath, 'utf8');
const localsRaw = fs.readFileSync(localsPath, 'utf8');
const items = parseTfvars(tfvarsRaw);
const defaults = parseRegionDefaults(localsRaw);
const markdown = buildMarkdown(items, defaults);

fs.mkdirSync(path.dirname(outputPath), {recursive: true});
fs.writeFileSync(outputPath, markdown);
console.log(`Wrote ${path.relative(process.cwd(), outputPath)}`);
