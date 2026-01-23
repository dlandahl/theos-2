Int_Set :: struct {
    BPW :: 32;
    words: [] u32;
}

cardinality :: (set: Int_Set) -> u64 {
    count: u64;
    for set.words {
        count += cast(u64) popcount(it);
    }
    return count;
}

is_set :: (set: Int_Set, i: int) -> bool {
    word := i / set.BPW;
    bit := 1 << (i & (set.BPW - 1));
    return (set.words[word] & bit) != 0;
}

#import "Bit_Operations";
