// Liquid-glass metaball fragment shader
// Extracted verbatim from the live deployed build (entry: index-Atg9aPoH.js).
//
// NOTE: In the original source this GLSL lives inside src/components/GlassBlob.tsx as a
// JavaScript template literal. The single token ${ol} below is a JS-injected value =
// the u_blobs array length, which is 6. It has been left as ${ol} where the source
// interpolates it; replace ${ol} with 6 to use this as a standalone .glsl file.

precision highp float;
varying vec2 v_uv;
uniform sampler2D u_scene;       // the html2canvas-captured page (tall texture)
uniform vec2 u_resolution;       // drawing-buffer size, for screen-space sampling
uniform vec3 u_blobs[${ol}];       // xy = pos (uv, y up), z = radius
uniform float u_normalStrength;
uniform float u_hasPointer;
uniform float u_scrollOffset;    // scrollY normalized into the content texture
uniform float u_viewFrac;        // viewport / content height
uniform float u_sceneValid;      // 1.0 when the captured page texture is real
uniform vec3 u_tint;             // glass tint so droplets read even with no scene
uniform float u_ior;             // index of refraction
uniform float u_glassThickness;  // refraction displacement (px-ish) before /res
uniform float u_displacementScale;
uniform float u_zoom;            // base magnification (lens enlargement)
uniform float u_sminK;           // corner-blend amount -> squircle curvature
uniform float u_transitionWidth; // sigmoid rim thickness (in p-space units)
uniform float u_cornerRadius;    // squircle corner radius
uniform float u_chromatic;       // extra per-channel spread (visible fringe)
uniform vec2  u_lightDir;        // light direction (lens center -> pointer)
uniform float u_highlightWidth;  // thin rim highlight band width
uniform float u_specularSize;    // tight specular exponent (120-200)
uniform float u_specularIntensity;

float aspect(){ return u_resolution.x/u_resolution.y; }

// map a screen uv (y up) into the tall captured-content texture, offset by the
// current scroll position so the page lines up with what's on screen.
vec2 toContentUV(vec2 screenUV){
  float topV = 1.0 - u_scrollOffset;
  float y = topV - (1.0 - screenUV.y) * u_viewFrac;
  return vec2(screenUV.x, y);
}

// smooth min / max (quartic-ish polynomial) used to round the box corners into
// a continuous-curvature squircle.
float sMin(float a, float b, float k){
  if (k <= 0.0) return min(a, b);
  float t = clamp(0.5 + 0.5*(b-a)/k, 0.0, 1.0);
  return mix(b, a, t) - k*t*(1.0-t);
}
float sMax(float a, float b, float k){
  if (k <= 0.0) return max(a, b);
  float t = clamp(0.5 + 0.5*(a-b)/k, 0.0, 1.0);
  return mix(b, a, t) + k*t*(1.0-t);
}

// signed distance to a SQUIRCLE (rounded box with smooth-blended corners).
// p, halfExtents, radius all in aspect-corrected p-space; k blends the corners.
float squircleSDF(vec2 p, vec2 halfExt, float r, float k){
  vec2 q = abs(p) - halfExt + r;
  if (k <= 0.0){
    return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - r;
  }
  float inner = sMin(sMax(q.x, q.y, k), 0.0, k*0.5);
  vec2 outer = vec2(sMax(q.x, 0.0, k), sMax(q.y, 0.0, k));
  return inner + length(outer) - r;
}

// METABALL lens: evaluate EVERY active blob in u_blobs as its own squircle and
// FUSE them with smin (u_sminK = fusion radius) into one organic field, so the
// sub-blobs trailing the pointer merge with a fluid neck (surface tension).
float lensSDF(vec2 p){
  float d = 1e9;
  for (int i = 0; i < ${ol}; i++){
    float rad = u_blobs[i].z;
    if (rad <= 0.0) continue;                 // skip inactive blobs
    vec2 c = u_blobs[i].xy; c.x *= aspect();
    float di = squircleSDF(p - c, vec2(rad), min(u_cornerRadius, rad*0.98), u_sminK);
    d = sMin(d, di, u_sminK);                  // smooth-min fuse -> metaball
  }
  return d;
}

// SIGMOID height from the SDF distance: flat (~1) across the interior, with a
// steep shoulder confined to a thin rim band of width u_transitionWidth.
float lensHeight(vec2 p){
  float d = lensSDF(p);
  float nd = d / max(1e-4, u_transitionWidth);
  return clamp(1.0 - 1.0/(1.0 + exp(-nd*6.0)), 0.0, 1.0);
}

void main(){
  if (u_hasPointer < 0.5) discard;

  // screen-space sampling coordinate (y up to match our normalized blob space)
  vec2 uv = gl_FragCoord.xy / u_resolution.xy;
  vec2 p = uv; p.x *= aspect();

  float d = lensSDF(p);

  // SIGMOID height: ~1 flat across the interior, steep shoulder confined to a
  // thin rim band (u_transitionWidth). Drives both the magnify and the normal.
  float h = lensHeight(p);

  // OUTSIDE the squircle -> fully transparent: the real HTML shows through
  if (h <= 0.001){
    gl_FragColor = vec4(0.0, 0.0, 0.0, 0.0);
    return;
  }

  // finite-difference normal from the sigmoid height field, averaged over two
  // step sizes for a clean gradient. Flat center => ~0 gradient => N~(0,0,1)
  // => no distortion; steep rim => large gradient => N tilts => sharp refract.
  vec2 s1 = vec2(0.75/u_resolution.x, 0.75/u_resolution.y);
  vec2 s2 = vec2(1.5/u_resolution.x, 1.5/u_resolution.y);
  float dx1 = lensHeight(p + vec2(s1.x,0.0)) - lensHeight(p - vec2(s1.x,0.0));
  float dy1 = lensHeight(p + vec2(0.0,s1.y)) - lensHeight(p - vec2(0.0,s1.y));
  float dx2 = lensHeight(p + vec2(s2.x,0.0)) - lensHeight(p - vec2(s2.x,0.0));
  float dy2 = lensHeight(p + vec2(0.0,s2.y)) - lensHeight(p - vec2(0.0,s2.y));
  float dx = (dx1 + dx2) * 0.5;
  float dy = (dy1 + dy2) * 0.5;

  vec3 normal = normalize(vec3(-dx*u_normalStrength, -dy*u_normalStrength, 1.0));

  // ---- BASE MAGNIFY toward the lens center (flat zoom in the middle) ----
  vec2 center = u_blobs[0].xy; center.x *= aspect();
  float zoomFactor = mix(1.0, u_zoom, h);
  vec2 muv = center + (p - center) / zoomFactor;
  muv.x /= aspect();                          // back to 0..1 uv for sampling

  // ---- TWO-PASS Snell refraction (enter through N, exit through -N), like a
  // real glass slab. Per-channel chromatic via perturbed normal AND IOR. ----
  vec3 I = vec3(0.0, 0.0, -1.0);
  float dispScale = u_glassThickness / u_resolution.y * u_displacementScale;

  // green / base
  vec3 inG  = refract(I, normal, 1.0/u_ior);
  vec3 outG = refract(inG, -normal, u_ior);
  bool tir = (dot(inG, inG) < 1e-6) || (dot(outG, outG) < 1e-6);

  // red (slightly weaker normal + lower IOR)
  vec3 nR = normalize(vec3(-dx*u_normalStrength*0.95, -dy*u_normalStrength*0.95, 1.0));
  vec3 inR  = refract(I, nR, 1.0/(u_ior*0.98));
  vec3 outR = refract(inR, -nR, u_ior*0.98);
  // blue (slightly stronger normal + higher IOR)
  vec3 nB = normalize(vec3(-dx*u_normalStrength*1.05, -dy*u_normalStrength*1.05, 1.0));
  vec3 inB  = refract(I, nB, 1.0/(u_ior*1.02));
  vec3 outB = refract(inB, -nB, u_ior*1.02);

  // R and B get an EXTRA outward spread so the colored fringe is clearly
  // visible at the rim (R pulled in, B pushed out from the green base).
  float spread = 1.0 + u_chromatic * 18.0;
  vec2 offG = outG.xy * dispScale;
  vec2 offR = (dot(outR,outR) < 1e-6 ? outG.xy : outR.xy) * dispScale * spread;
  vec2 offB = (dot(outB,outB) < 1e-6 ? outG.xy : outB.xy) * dispScale * (2.0 - spread);

  vec3 refrColor;
  if (u_sceneValid > 0.5){
    float rC = texture2D(u_scene, toContentUV(muv + offR)).r;
    float gC = texture2D(u_scene, toContentUV(muv + offG)).g;
    float bC = texture2D(u_scene, toContentUV(muv + offB)).b;
    refrColor = vec3(rC, gC, bC);
  } else {
    refrColor = u_tint; // no captured page -> glass tint base, never empty
  }

  // ---- FRESNEL MIX (refraction vs reflection); TIR -> reflection, no black ----
  float fresEdge = 1.0 - abs(normal.z); fresEdge *= fresEdge; // tiny edge cue
  vec3 reflColor = u_tint;
  vec3 glass = mix(refrColor, reflColor, clamp(fresEdge * 0.5, 0.0, 1.0));
  if (tir) glass = reflColor;
  vec3 col = glass;

  // ---- HARD WATER-LIKE REFLECTIONS (razor-thin rim line + tiny hard glint) ----
  // EXTREMELY HARD specular: very high exponent, then a near on/off gate so only
  // the brightest core survives as a tiny sharp glint (no soft lobe).
  vec3 lightDir3 = normalize(vec3(u_lightDir, 0.8));
  float surfaceSpec = pow(max(dot(normal, lightDir3), 0.0), u_specularSize);
  surfaceSpec = smoothstep(0.6, 0.95, surfaceSpec); // hard-gate: crisp spot only

  // RAZOR-THIN rim line: brightness ~0 except within a 1-2px band at abs(d)~=0
  float ad = abs(lensSDF(p));
  float rimMask = 1.0 - smoothstep(0.0, u_highlightWidth, ad);
  rimMask = pow(rimMask, 6.0); // sharpen toward a step -> thin white line

  // localize the rim hot spot toward the light direction (not a uniform ring)
  float NdotLnorm = dot(normal.xy, u_lightDir) / (length(normal.xy) + 0.001);
  float nearDrop = 1.0 - max(NdotLnorm, 0.0);
  float farDrop  = 1.0 - max(-NdotLnorm, 0.0);
  float nearFactor = 1.0 / (1.0 + 60.0 * nearDrop*nearDrop*nearDrop);
  float farFactor  = 1.0 / (1.0 + 60.0 * farDrop*farDrop*farDrop);
  float rimTotal = rimMask * (nearFactor * 0.9 + farFactor * 0.45);

  // Fresnel body-bleed killed to ~0 so there's NO soft gradient across the body
  float fresnel = (1.0 - abs(normal.z)); fresnel *= fresnel;
  float specTotal = clamp(
    (rimTotal + surfaceSpec + fresnel * 0.02) * u_specularIntensity,
    0.0, 1.0);

  // Pass 1: white specular via SCREEN blend (specTotal ~0 across the interior)
  col = 1.0 - (1.0 - col) * (1.0 - vec3(specTotal));

  // Pass 2: saturation boost gated ONLY on the tiny rim sliver (no smear)
  float satBoost = clamp(rimTotal * u_specularIntensity * 2.4, 0.0, 1.0);
  float luma = dot(col, vec3(0.2126, 0.7152, 0.0722));
  vec3 sat = max(vec3(0.0), mix(vec3(luma), col, 1.0 + satBoost * 6.0));
  col = mix(col, sat, satBoost);

  col = max(col, vec3(0.0));

  // coverage alpha from the SDF silhouette
  float cover = smoothstep(1.5/u_resolution.y, -1.5/u_resolution.y, d);
  float lit = clamp(specTotal, 0.0, 1.0);
  float alpha = cover * (u_sceneValid > 0.5 ? 1.0 : mix(0.55, 1.0, max(h, lit)));
  gl_FragColor = vec4(col, alpha);
}
