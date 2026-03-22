import fs from 'node:fs';
import path from 'node:path';

const repoRoot = path.resolve(process.cwd(), '..');
const tfvarsPath = path.join(
  repoRoot,
  'soperator',
  'installations',
  'example',
  'terraform.tfvars',
);
const platformPath = path.join(
  repoRoot,
  'soperator',
  'modules',
  'available_resources',
  'platform.tf',
);
const presetPath = path.join(
  repoRoot,
  'soperator',
  'modules',
  'available_resources',
  'preset.tf',
);
const outputPath = path.join(
  repoRoot,
  'website',
  'docs',
  'soperator',
  'generated-configuration-reference.md',
);

function cleanCommentLine(line) {
  return line.replace(/^\s*#\s?/, '').trimEnd();
}

function isDivider(line) {
  return /^#-+$/.test(line.trim()) || /^#$/.test(line.trim());
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

    if (/^[-#\s|]+$/.test(trimmed)) {
      continue;
    }

    if (/^terraform\s*-\s*example values/i.test(trimmed)) {
      continue;
    }

    if (/^region\s+/i.test(trimmed) || /^endregion\s+/i.test(trimmed) || trimmed === '---') {
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

function parseTfvarsSections(raw) {
  const lines = raw.split('\n');
  const sections = [];
  let sectionStack = [];
  let pendingComments = [];

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    const trimmed = line.trim();

    const regionMatch = trimmed.match(/^#\s*region\s+(.+)$/i);
    if (regionMatch) {
      sectionStack.push(regionMatch[1].trim());
      pendingComments = [];
      continue;
    }

    const endRegionMatch = trimmed.match(/^#\s*endregion\b/i);
    if (endRegionMatch) {
      sectionStack.pop();
      pendingComments = [];
      continue;
    }

    if (trimmed.startsWith('#')) {
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
    const commentLines = sanitizeCommentBlock(pendingComments);
    const exampleLines = [line];
    let balance = countDelta(line);
    let j = i + 1;

    while (j < lines.length && balance > 0) {
      exampleLines.push(lines[j]);
      balance += countDelta(lines[j]);
      j += 1;
    }

    sections.push({
      name,
      sectionPath: [...sectionStack],
      comments: commentLines,
      example: exampleLines.join('\n').trimEnd(),
    });

    i = j - 1;
    pendingComments = [];
  }

  return sections;
}

function parsePlatforms(raw) {
  const blockMatch = raw.match(/platforms\s*=\s*\{([\s\S]*?)\n\s*\}/);
  if (!blockMatch) {
    return [];
  }

  return [...blockMatch[1].matchAll(/([a-z0-9-]+)\s*=\s*"([^"]+)"/g)].map(
    (match) => match[2],
  );
}

function parsePlatformRegions(raw) {
  const regionMap = new Map();
  const lines = raw.split('\n');
  let currentPlatform = null;

  for (const line of lines) {
    const platformMatch = line.match(/\(local\.platforms\.([a-z0-9_-]+)\)\s*=\s*\[/);
    if (platformMatch) {
      currentPlatform = platformMatch[1].replace(/_/g, '-');
      regionMap.set(currentPlatform, []);
      continue;
    }

    if (currentPlatform) {
      const regionMatch = line.match(/local\.regions\.([a-z0-9_-]+)/);
      if (regionMatch) {
        regionMap.get(currentPlatform).push(regionMatch[1].replace(/_/g, '-'));
      }

      if (line.trim() === ']') {
        currentPlatform = null;
      }
    }
  }

  return regionMap;
}

function parsePresetDetails(raw) {
  const details = new Map();
  const blockRegex =
    /([cg]-[\dgpuvc-]+gb)\s*=\s*\{([\s\S]*?)\n\s*\}/g;

  for (const match of raw.matchAll(blockRegex)) {
    const key = match[1];
    const body = match[2];
    const cpu = body.match(/cpu_cores\s*=\s*(\d+)/);
    const memory = body.match(/memory_gibibytes\s*=\s*(\d+)/);
    const gpus = body.match(/gpus\s*=\s*(\d+)/);
    const gpuClusterCompatible = body.match(/gpu_cluster_compatible\s*=\s*(true|false)/);

    details.set(key, {
      cpu: cpu ? Number(cpu[1]) : null,
      memory: memory ? Number(memory[1]) : null,
      gpus: gpus ? Number(gpus[1]) : null,
      gpuClusterCompatible: gpuClusterCompatible
        ? gpuClusterCompatible[1] === 'true'
        : false,
    });
  }

  return details;
}

function parsePresetsByPlatform(raw) {
  const map = new Map();
  const lines = raw.split('\n');
  let currentPlatform = null;

  for (const line of lines) {
    const platformMatch = line.match(/\(local\.platforms\.([a-z0-9_-]+)\)\s*=\s*tomap\(\{/);
    if (platformMatch) {
      currentPlatform = platformMatch[1].replace(/_/g, '-');
      map.set(currentPlatform, []);
      continue;
    }

    if (currentPlatform) {
      const presetMatch = line.match(
        /\(local\.presets\.([a-z0-9_-]+)\)\s*=\s*local\.presets_(cpu|gpu)\.([a-z0-9-]+)/,
      );
      if (presetMatch) {
        map.get(currentPlatform).push({
          display: presetAliasToDisplay(presetMatch[1]),
          detailKey: presetMatch[3],
        });
      }

      if (line.trim() === '})') {
        currentPlatform = null;
      }
    }
  }

  return map;
}

function presetAliasToDisplay(alias) {
  const parts = alias.split('-');
  if (parts[1]?.endsWith('g')) {
    return `${parts[1].slice(0, -1)}gpu-${parts[2].slice(0, -1)}vcpu-${parts[3].slice(0, -1)}gb`;
  }
  return `${parts[1].slice(0, -1)}vcpu-${parts[2].slice(0, -1)}gb`;
}

function formatCommentBlock(comments) {
  if (comments.length === 0) {
    return '_No inline description in `terraform.tfvars`._';
  }

  const filtered = comments.filter(
    (line) =>
      !/^or use existing/i.test(line) &&
      !/^filestore_/i.test(line) &&
      !/^node_local_/i.test(line) &&
      !/^nfs\s*=/.test(line),
  );

  return filtered
    .map((line) => {
      const trimmed = line.trim();
      if (trimmed.startsWith('- ')) {
        return `- ${trimmed.slice(2)}`;
      }
      return trimmed;
    })
    .join('\n');
}

function buildMarkdown({sections, platforms, platformRegions, presetsByPlatform, presetDetails}) {
  const generatedAt = new Date().toISOString().slice(0, 10);
  const grouped = new Map();

  for (const section of sections) {
    const key = section.sectionPath.join(' / ') || 'General';
    if (!grouped.has(key)) {
      grouped.set(key, []);
    }
    grouped.get(key).push(section);
  }

  const lines = [
    '---',
    'sidebar_position: 5',
    '---',
    '',
    '# Generated Configuration Reference',
    '',
    `This page is generated from \`soperator/installations/example/terraform.tfvars\` comments plus resource metadata in \`soperator/modules/available_resources\`.`,
    '',
    `Generation date: ${generatedAt}`,
    '',
    '## Why this page exists',
    '',
    '- The example `terraform.tfvars` already contains operator guidance worth preserving.',
    '- The Terraform resource metadata adds useful context for platforms, presets, and GPU-cluster capability.',
    '- This page is meant to stay close to the repo instead of becoming a manually curated summary that drifts.',
    '',
    '## Platform and preset catalog',
    '',
  ];

  for (const platform of platforms) {
    lines.push(`### \`${platform}\``);
    const regions = platformRegions.get(platform) || [];
    const presets = presetsByPlatform.get(platform) || [];
    lines.push('');
    lines.push(`- Regions: ${regions.length > 0 ? regions.map((region) => `\`${region}\``).join(', ') : 'n/a'}`);
    if (presets.length > 0) {
      lines.push('- Presets:');
      for (const preset of presets) {
        const details = presetDetails.get(preset.detailKey);
        const detailBits = [];
        if (details?.cpu != null) {
          detailBits.push(`${details.cpu} vCPU`);
        }
        if (details?.memory != null) {
          detailBits.push(`${details.memory} GiB RAM`);
        }
        if (details?.gpus != null) {
          detailBits.push(`${details.gpus} GPU`);
        }
        if (details?.gpuClusterCompatible) {
          detailBits.push('GPU-cluster compatible');
        }
        lines.push(`  - \`${preset.display}\`${detailBits.length > 0 ? `: ${detailBits.join(', ')}` : ''}`);
      }
    }
    lines.push('');
  }

  lines.push('## Variable catalog');
  lines.push('');

  for (const [groupName, items] of grouped) {
    lines.push(`## ${groupName}`);
    lines.push('');

    for (const item of items) {
      lines.push(`### \`${item.name}\``);
      lines.push('');
      lines.push(formatCommentBlock(item.comments));
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
  lines.push('npm run generate:soperator-docs');
  lines.push('```');
  lines.push('');

  return `${lines.join('\n')}\n`;
}

const tfvarsRaw = fs.readFileSync(tfvarsPath, 'utf8');
const platformRaw = fs.readFileSync(platformPath, 'utf8');
const presetRaw = fs.readFileSync(presetPath, 'utf8');

const markdown = buildMarkdown({
  sections: parseTfvarsSections(tfvarsRaw),
  platforms: parsePlatforms(platformRaw),
  platformRegions: parsePlatformRegions(platformRaw),
  presetsByPlatform: parsePresetsByPlatform(presetRaw),
  presetDetails: parsePresetDetails(presetRaw),
});

fs.mkdirSync(path.dirname(outputPath), {recursive: true});
fs.writeFileSync(outputPath, markdown);
console.log(`Wrote ${path.relative(process.cwd(), outputPath)}`);
