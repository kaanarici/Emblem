import fs from 'fs';
import path from 'path';
import crypto from 'crypto';
const [esm, mapFile, catalog, swiftOut] = process.argv.slice(2);
const map = fs.readFileSync(mapFile, 'utf8').trim().split('\n').map(l => l.trim().split(/\s+/));
const icons = [...new Set(map.map(m => m[1]))].sort();
const dir = path.join(catalog, 'Hugeicons');
fs.rmSync(dir, {recursive: true, force: true});
fs.mkdirSync(dir, {recursive: true});
fs.writeFileSync(path.join(dir, 'Contents.json'), JSON.stringify({info: {author: 'xcode', version: 1}, properties: {'provides-namespace': true}}, null, 2) + '\n');
const attr = o => Object.entries(o).filter(([k]) => k !== 'key')
  .map(([k, v]) => `${k.replace(/[A-Z]/g, m => '-' + m.toLowerCase())}="${v === 'currentColor' ? '#000000' : v}"`).join(' ');
const hashes = [];

const FILL_SF_MAP = {
  'clock.fill':               'Clock01',
  'rosette.fill':             'StarAward01',
  'phone.fill':               'Telephone',
  'phone.circle.fill':        'Telephone',
  'envelope.fill':            'Mail01',
  'star.fill':                'Star',
  'heart.fill':               'Favourite',
  'location.fill':            'Location01',
  'mappin.fill':              'Location01',
  'mappin.and.ellipse.fill':  'PinLocation01',
  'bell.fill':                'Bell',
  'bookmark.fill':            'Bookmark02',
  'person.fill':              'User',
  'person.crop.circle.fill':  'UserCircle',
  'house.fill':               'Home01',
  'flag.fill':                'Flag01',
  'checkmark.circle.fill':    'CheckmarkCircle02',
  'xmark.circle.fill':        'CancelCircle',
  'plus.circle.fill':         'AddCircle',
  'info.circle.fill':         'InformationCircle',
};
const FILL_TARGETS = [...new Set(Object.values(FILL_SF_MAP))];

function approxBBox(d) {
  if (!d) return { x1: 0, y1: 0, x2: 24, y2: 24 };
  const nums = [...d.matchAll(/[-+]?[0-9]*\.?[0-9]+(?:\.[0-9]+)?/g)].map(m => parseFloat(m[0]));
  const xs = [], ys = [];
  for (let i = 0; i + 1 < nums.length; i += 2) { xs.push(nums[i]); ys.push(nums[i + 1]); }
  if (!xs.length) return { x1: 0, y1: 0, x2: 24, y2: 24 };
  return { x1: Math.min(...xs), y1: Math.min(...ys), x2: Math.max(...xs), y2: Math.max(...ys) };
}

function circleBBox(attrs) {
  const cx = parseFloat(attrs.cx || 0), cy = parseFloat(attrs.cy || 0), r = parseFloat(attrs.r || 0);
  return { x1: cx - r, y1: cy - r, x2: cx + r, y2: cy + r };
}

function bboxArea(b) { return Math.max(0, b.x2 - b.x1) * Math.max(0, b.y2 - b.y1); }

function bboxInside(a, b, tol = 1.0) {
  return a.x1 >= b.x1 - tol && a.y1 >= b.y1 - tol && a.x2 <= b.x2 + tol && a.y2 <= b.y2 + tol;
}

function isClosed(d) { return /[Zz]\s*$/.test((d || '').trim()); }

function circleToPath({ cx, cy, r }) {
  const [x, y, rv] = [parseFloat(cx), parseFloat(cy), parseFloat(r)];
  return `M${x + rv},${y}A${rv},${rv},0,1,1,${x - rv},${y}A${rv},${rv},0,1,1,${x + rv},${y}Z`;
}

function strokeExtra(attrs) {
  let s = '';
  if (attrs.strokeLinecap) s += ` stroke-linecap="${attrs.strokeLinecap}"`;
  if (attrs.strokeLinejoin) s += ` stroke-linejoin="${attrs.strokeLinejoin}"`;
  return s;
}

function makeFillSvg(name, nodes) {
  const closed = [], others = [];
  for (const [tag, a] of nodes) {
    const d = a.d || '';
    const isCircle = tag === 'circle';
    const isClosedShape = isCircle || tag === 'rect' || tag === 'ellipse' || tag === 'polygon' ||
      (tag === 'path' && isClosed(d));
    const bbox = isCircle ? circleBBox(a) : approxBBox(d);
    const pathD = isCircle ? circleToPath(a) : d;
    if (isClosedShape) closed.push({ tag, a, d: pathD, bbox });
    else others.push({ tag, a, d, bbox });
  }

  if (!closed.length) {
    const els = nodes.map(([t, a]) => `<${t} ${attr({...a, stroke: '#000000', fill: 'none'})}/>`);
    return `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">${els.join('')}</svg>\n`;
  }

  closed.sort((a, b) => bboxArea(b.bbox) - bboxArea(a.bbox));

  const outer = closed[0];
  const holes = closed.slice(1).filter(s => bboxInside(s.bbox, outer.bbox));
  const separateSolids = closed.slice(1).filter(s => !bboxInside(s.bbox, outer.bbox));

  const knockout = others.filter(n => n.tag === 'path' && bboxInside(n.bbox, outer.bbox, -1));
  const strokes = others.filter(n => !knockout.includes(n));

  const parts = [];
  const needsMask = knockout.length > 0;
  const maskId = 'm';

  if (needsMask) {
    const mkPaths = knockout.map(n =>
      `<path d="${n.d}" stroke="black" stroke-width="${n.a.strokeWidth || '1.5'}" fill="none"${strokeExtra(n.a)}/>`
    ).join('');
    parts.push(`<mask id="${maskId}"><rect width="24" height="24" fill="white"/>${mkPaths}</mask>`);
  }

  const combinedD = [outer, ...holes].map(s => s.d).join(' ');
  const fillRule = holes.length > 0 ? ' fill-rule="evenodd"' : '';
  const maskAttr = needsMask ? ` mask="url(#${maskId})"` : '';
  parts.push(`<path d="${combinedD}" fill="#000000"${fillRule}${maskAttr}/>`);

  for (const [tag, a] of nodes) {
    const d = a.d || '';
    const pathD = tag === 'circle' ? circleToPath(a) : d;
    const isInSeparate = separateSolids.some(s => s.d === pathD);
    if (!isInSeparate) continue;
    if (tag === 'circle') {
      parts.push(`<circle cx="${a.cx}" cy="${a.cy}" r="${a.r}" fill="#000000" stroke="#000000" stroke-width="1.5"/>`);
    } else {
      const sa = strokeExtra(a);
      parts.push(`<path d="${d}" fill="#000000" stroke="#000000" stroke-width="${a.strokeWidth || '1.5'}"${sa}/>`);
    }
  }

  for (const { a, d } of strokes) {
    const sa = strokeExtra(a);
    parts.push(`<path d="${d}" fill="none" stroke="#000000" stroke-width="${a.strokeWidth || '1.5'}"${sa}/>`);
  }

  return `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">${parts.join('')}</svg>\n`;
}

for (const name of icons) {
  const file = `${esm}/${name}Icon.js`;
  const src = fs.readFileSync(file, 'utf8');
  hashes.push(`package/dist/esm/${name}Icon.js ${crypto.createHash('sha256').update(src).digest('hex')}`);
  const nodes = eval(src.slice(src.indexOf('['), src.lastIndexOf('];') + 1));
  const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none">${nodes.map(([t, a]) => `<${t} ${attr(a)}/>`).join('')}</svg>\n`;
  const set = path.join(dir, `${name}.imageset`);
  fs.mkdirSync(set);
  fs.writeFileSync(path.join(set, `${name}.svg`), svg);
  fs.writeFileSync(path.join(set, 'Contents.json'), JSON.stringify({
    images: [{filename: `${name}.svg`, idiom: 'universal'}],
    info: {author: 'xcode', version: 1},
    properties: {'preserves-vector-representation': true, 'template-rendering-intent': 'template'},
  }, null, 2) + '\n');
}

const fillIconsGenerated = [];
for (const name of FILL_TARGETS) {
  const file = `${esm}/${name}Icon.js`;
  if (!fs.existsSync(file)) continue;
  const src = fs.readFileSync(file, 'utf8');
  const nodes = eval(src.slice(src.indexOf('['), src.lastIndexOf('];') + 1));
  const fillName = `${name}Fill`;
  const svg = makeFillSvg(name, nodes);
  const set = path.join(dir, `${fillName}.imageset`);
  fs.mkdirSync(set, {recursive: true});
  fs.writeFileSync(path.join(set, `${fillName}.svg`), svg);
  fs.writeFileSync(path.join(set, 'Contents.json'), JSON.stringify({
    images: [{filename: `${fillName}.svg`, idiom: 'universal'}],
    info: {author: 'xcode', version: 1},
    properties: {'preserves-vector-representation': true, 'template-rendering-intent': 'template'},
  }, null, 2) + '\n');
  fillIconsGenerated.push(fillName);
}

const entries = map.map(([sf, hi]) => `        "${sf}": "${hi}",`).join('\n');
const fillEntries = Object.entries(FILL_SF_MAP)
  .filter(([, hi]) => fillIconsGenerated.includes(`${hi}Fill`))
  .map(([sf, hi]) => `        "${sf}": "${hi}Fill",`)
  .join('\n');

fs.writeFileSync(swiftOut, `import SwiftUI
import UIKit

enum Hugeicons {
    static func asset(for symbol: String?) -> String? {
        guard var name = symbol?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !name.isEmpty else { return nil }
        while true {
            if let hit = map[name] { return "Hugeicons/" + hit }
            if name.hasSuffix(".fill") {
                name.removeLast(5)
            } else if let dot = name.lastIndex(of: ".") {
                name = String(name[..<dot])
            } else {
                return nil
            }
        }
    }

    static func isRenderable(_ symbol: String?) -> Bool {
        guard let symbol, !symbol.isEmpty else { return false }
        return asset(for: symbol) != nil || UIImage(systemName: symbol) != nil
    }

    private static let map: [String: String] = [
${entries}
${fillEntries}
    ]
}

struct GlyphImage: View {
    let symbol: String
    var size: CGFloat
    var weight: Font.Weight = .medium

    var body: some View {
        if let asset = Hugeicons.asset(for: symbol) {
            Image(asset)
                .resizable()
                .renderingMode(.template)
                .interpolation(.high)
                .frame(width: size, height: size)
        } else {
            Image(systemName: symbol)
                .font(.system(size: size * 0.82, weight: weight))
                .frame(width: size, height: size)
        }
    }
}
`);
fs.writeFileSync(process.env.HASHES_OUT ?? '/dev/null', hashes.join('\n') + '\n');
console.log(icons.length, 'stroke icons,', fillIconsGenerated.length, 'fill variants,', map.length, 'mappings');
