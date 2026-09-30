//! Row-band parallelism for per-pixel operations.

/// Calls `f(y, row)` for every row of `out` (rows of `row_len` values),
/// spreading bands of consecutive rows over the available cores. Each row
/// is computed exactly as it would be sequentially, so the result does not
/// depend on the number of threads.
pub(crate) fn rows<F>(out: &mut [f32], row_len: usize, f: F)
where
    F: Fn(usize, &mut [f32]) + Sync,
{
    let cores = std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1);
    rows_with(out, row_len, cores, f);
}

/// [`rows`] on at most `threads` threads.
fn rows_with<F>(out: &mut [f32], row_len: usize, threads: usize, f: F)
where
    F: Fn(usize, &mut [f32]) + Sync,
{
    if row_len == 0 || out.is_empty() {
        return;
    }
    let h = out.len() / row_len;
    // At least 16 rows per band: smaller bands cost more to spawn than to run.
    let workers = threads.min(h / 16).max(1);
    if workers == 1 {
        out.chunks_mut(row_len).enumerate().for_each(|(y, row)| f(y, row));
        return;
    }
    let per = h.div_ceil(workers);
    std::thread::scope(|s| {
        for (b, band) in out.chunks_mut(per * row_len).enumerate() {
            let f = &f;
            s.spawn(move || {
                for (r, row) in band.chunks_mut(row_len).enumerate() {
                    f(b * per + r, row);
                }
            });
        }
    });
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn every_row_is_visited_once_with_its_index_whatever_the_thread_count() {
        for (rows, threads) in [(1, 8), (15, 4), (16, 2), (100, 3), (100, 7), (257, 64)] {
            let mut out = vec![0f32; rows * 5];
            rows_with(&mut out, 5, threads, |y, row| {
                assert_eq!(row.len(), 5);
                row.iter_mut().enumerate().for_each(|(x, v)| *v += (y * 5 + x) as f32);
            });
            assert!(out.iter().enumerate().all(|(i, &v)| v == i as f32), "{rows} rows, {threads} threads");
        }
    }
}
