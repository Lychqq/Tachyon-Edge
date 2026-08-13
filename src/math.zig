const std = @import("std");

/// Computes the cosine similarity between two float16 vectors.
/// Uses SIMD where possible, falling back to scalar operations for the remainder.
/// Returns a f32 value between -1.0 (opposite) and 1.0 (identical).
pub fn cosineSimilarity(a: []const f16, b: []const f16) !f32 {
    if (a.len != b.len) return error.VectorLengthMismatch;
    if (a.len == 0) return 0.0;

    const simd_len = std.simd.suggestVectorLength(f16) orelse 1;

    var dot_sum: f32 = 0.0;
    var norm_a_sum: f32 = 0.0;
    var norm_b_sum: f32 = 0.0;

    var i: usize = 0;

    if (simd_len > 1) {
        const Vec16 = @Vector(simd_len, f16);
        const Vec32 = @Vector(simd_len, f32);

        var v_dot = @as(Vec32, @splat(0.0));
        var v_norm_a = @as(Vec32, @splat(0.0));
        var v_norm_b = @as(Vec32, @splat(0.0));

        while (i + simd_len <= a.len) : (i += simd_len) {
            const va16: Vec16 = a[i .. i + simd_len][0..simd_len].*;
            const vb16: Vec16 = b[i .. i + simd_len][0..simd_len].*;

            // Cast to f32 for math operations
            const va: Vec32 = @floatCast(va16);
            const vb: Vec32 = @floatCast(vb16);

            v_dot += va * vb;
            v_norm_a += va * va;
            v_norm_b += vb * vb;
        }

        dot_sum = @reduce(.Add, v_dot);
        norm_a_sum = @reduce(.Add, v_norm_a);
        norm_b_sum = @reduce(.Add, v_norm_b);
    }

    // Handle the remainder
    while (i < a.len) : (i += 1) {
        const val_a: f32 = @floatCast(a[i]);
        const val_b: f32 = @floatCast(b[i]);

        dot_sum += val_a * val_b;
        norm_a_sum += val_a * val_a;
        norm_b_sum += val_b * val_b;
    }

    if (norm_a_sum == 0.0 or norm_b_sum == 0.0) return 0.0;

    return dot_sum / (@sqrt(norm_a_sum) * @sqrt(norm_b_sum));
}

/// Computes cosine distance (1.0 - cosine_similarity).
/// Returns a value between 0.0 (identical) and 2.0 (opposite).
pub fn cosineDistance(a: []const f16, b: []const f16) !f32 {
    const sim = try cosineSimilarity(a, b);
    return 1.0 - sim;
}

test "cosine similarity and distance" {
    const testing = std.testing;

    // Test identical vectors
    const v1 = [_]f16{ 1.0, 2.0, 3.0 };
    const sim_identical = try cosineSimilarity(&v1, &v1);
    try testing.expectApproxEqAbs(@as(f32, 1.0), sim_identical, 1e-4);

    // Test orthogonal vectors
    const v2 = [_]f16{ 1.0, 0.0, 0.0 };
    const v3 = [_]f16{ 0.0, 1.0, 0.0 };
    const sim_ortho = try cosineSimilarity(&v2, &v3);
    try testing.expectApproxEqAbs(@as(f32, 0.0), sim_ortho, 1e-4);

    // Test opposite vectors
    const v4 = [_]f16{ -1.0, -2.0, -3.0 };
    const sim_opp = try cosineSimilarity(&v1, &v4);
    try testing.expectApproxEqAbs(@as(f32, -1.0), sim_opp, 1e-4);

    // Test non-multiple of SIMD register size
    var v_large1: [100]f16 = undefined;
    var v_large2: [100]f16 = undefined;

    for (&v_large1, 0..) |*item, i| {
        item.* = @floatFromInt(i);
    }
    for (&v_large2, 0..) |*item, i| {
        item.* = @floatFromInt(i * 2);
    }

    const sim_large = try cosineSimilarity(&v_large1, &v_large2);
    try testing.expectApproxEqAbs(@as(f32, 1.0), sim_large, 1e-4); // Should be 1.0 because they are proportional

    const dist_large = try cosineDistance(&v_large1, &v_large2);
    try testing.expectApproxEqAbs(@as(f32, 0.0), dist_large, 1e-4);
}
