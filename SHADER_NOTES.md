# Liquid-glass metaball shader

This repository currently contains the **fragment shader** for the liquid-glass
metaball lens used on the live site, extracted verbatim from the deployed build
(entry bundle `index-Atg9aPoH.js`).

## File

- `src/shaders/glass.frag.glsl` — the complete fragment shader.

## Important notes

- In the original project source, this GLSL lives **inside `src/components/GlassBlob.tsx`**
  as a JavaScript template literal (not a standalone `.glsl` file).
- The token `${ol}` in the shader is a **JavaScript-injected value** = the length of
  the `u_blobs` array, which is **6**. It appears in two places:
  - `uniform vec3 u_blobs[${ol}];`
  - `for (int i = 0; i < ${ol}; i++)`
  Replace `${ol}` with `6` to compile this as a plain `.glsl` file.

## What's included in the shader

- `smin`-based **metaball fusion loop** over all active blobs (organic surface tension).
- **Squircle SDF** (`squircleSDF`) with smooth-min/max corner blending.
- **Sigmoid height** field driving the magnify and the surface normal.
- **Two-pass Snell's-law refraction** (enter through N, exit through -N).
- **Per-channel chromatic aberration** (normal 0.95/1.05 + IOR 0.98/1.02 + extra spread).
- **Razor-thin rim highlight** (`pow(rimMask, 6.0)`).
- **Hard-gated specular** (`smoothstep(0.6, 0.95, surfaceSpec)`) for a crisp water glint.

## Caveat

This is the fragment shader only, recovered from the deployed (minified) bundle —
the GLSL itself is stored as a string so it came through intact and unminified.
The rest of the project source (the TanStack Start app: `src/components/GlassBlob.tsx`,
`InkField.tsx`, routes, config, fonts, portrait assets) is **not** in this repo yet.
