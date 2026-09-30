//! Length-limited Huffman code construction shared by the DEFLATE and
//! JPEG encoders.

/// Code lengths for `freqs`, limited to `max_len`, always forming a
/// complete prefix code over at least two symbols.
pub fn huffman_lengths(freqs: &[u32], max_len: u8) -> Vec<u8> {
    let mut freqs = freqs.to_vec();
    let mut used: Vec<usize> = (0..freqs.len()).filter(|&i| freqs[i] > 0).collect();
    // A complete code needs at least two symbols.
    for (i, f) in freqs.iter_mut().enumerate() {
        if used.len() >= 2 {
            break;
        }
        if *f == 0 {
            *f = 1;
            used.push(i);
        }
    }
    let mut lengths = vec![0u8; freqs.len()];
    // Build the tree by repeatedly merging the two lightest nodes.
    let mut heap: std::collections::BinaryHeap<std::cmp::Reverse<(u64, usize)>> =
        used.iter().map(|&i| std::cmp::Reverse((u64::from(freqs[i]), i))).collect();
    let mut parent: Vec<usize> = vec![usize::MAX; freqs.len()];
    let mut next = freqs.len();
    while heap.len() > 1 {
        let std::cmp::Reverse((fa, a)) = heap.pop().expect("heap has two nodes");
        let std::cmp::Reverse((fb, b)) = heap.pop().expect("heap has two nodes");
        parent.resize(next + 1, usize::MAX);
        parent[a] = next;
        parent[b] = next;
        heap.push(std::cmp::Reverse((fa + fb, next)));
        next += 1;
    }
    for &s in &used {
        let (mut d, mut n) = (0u32, s);
        while parent[n] != usize::MAX {
            n = parent[n];
            d += 1;
        }
        lengths[s] = d.min(u32::from(max_len)) as u8;
    }
    // Restore the Kraft equality after clamping.
    let unit = |l: u8| 1u64 << (max_len - l);
    let target = 1u64 << max_len;
    let mut kraft: u64 = used.iter().map(|&s| unit(lengths[s])).sum();
    let mut by_len: Vec<usize> = used.clone();
    by_len.sort_by_key(|&s| (std::cmp::Reverse(lengths[s]), freqs[s]));
    while kraft > target {
        // Lengthen the longest code that is still below the limit.
        let s = *by_len
            .iter()
            .filter(|&&s| lengths[s] < max_len)
            .max_by_key(|&&s| (lengths[s], std::cmp::Reverse(freqs[s])))
            .expect("a code below the limit exists");
        kraft -= unit(lengths[s]) / 2;
        lengths[s] += 1;
    }
    while kraft < target {
        // Shorten the longest code whose shortening still fits.
        let candidate = used
            .iter()
            .copied()
            .filter(|&s| lengths[s] > 1 && kraft + unit(lengths[s]) <= target)
            .max_by_key(|&s| (lengths[s], freqs[s]));
        match candidate {
            Some(s) => {
                kraft += unit(lengths[s]);
                lengths[s] -= 1;
            }
            None => break,
        }
    }
    debug_assert_eq!(kraft, target, "encoder produced an incomplete code");
    lengths
}
