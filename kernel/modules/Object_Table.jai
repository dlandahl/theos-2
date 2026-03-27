
// Like Bucket_Array with generational IDs added on.
// We also format the bucket index, slot index, and generation into a 64-bit integer that can fit in a register.

#scope_module

#import "Bucket_Array";
#import "Bitfield";

set          :: bitfield_set;
get          :: bitfield_get;

#scope_export

Object_Table :: struct (Object: Type) {
    array: Bucket_Array(Tagged, 256);

    Tagged :: struct {
        #as object: Object;
        generation: u32;
    }
}

check_generation :: (using table: *Object_Table, locator: Bucket_Locator, generation: u32) -> *table.Tagged {
    if locator.slot_index > 256 {
        return null;
    }

    if locator.bucket_index >= array.all_buckets.count  {
        return null;
    }

    bucket := array.all_buckets[locator.bucket_index];

    if !bucket.occupied[locator.slot_index] {
        return null;
    }

    slot := *bucket.data[locator.slot_index];

    return ifx slot.generation == generation then slot else null;
}

// 8 bits for the slot index, leaves 24 for the bucket index and 32 for generation.
Handle :: enum u64 {
    slot_index     :: 8;
    bucket_index   :: 24;
    generation     :: 32;
}

add_object :: (table: *Object_Table) -> *table.Object, id: u64 {
    slot, locator := find_and_occupy_empty_slot(*table.array, false); // Don't initialize, so the generation value stays around.

    handle: Handle = ---;
    set(*handle, .slot_index,   locator.slot_index);
    set(*handle, .bucket_index, locator.bucket_index);
    set(*handle, .generation,   slot.generation);

    return slot, cast(u64) handle;
}

remove_object :: (table: *Object_Table, id: u64) -> bool {
    handle := cast(Handle) id;

    locator: Bucket_Locator;
    locator.slot_index    = cast(s32) get(handle, .slot_index);
    locator.bucket_index  = cast(u32) get(handle, .bucket_index);
    generation           := cast(u32) get(handle, .generation);

    slot := check_generation(table, locator, generation);
    if slot == null return false; // The slot isn't occupied, or the generation doesn't match.

    bucket_array_remove(*table.array, locator);
    slot.generation += 1;

    return true;
}

lookup :: (table: *Object_Table, id: u64) -> *table.Object {
    handle := cast(Handle) id;

    locator: Bucket_Locator;
    locator.slot_index    = cast(s32) get(handle, .slot_index);
    locator.bucket_index  = cast(u32) get(handle, .bucket_index);
    generation           := cast(u32) get(handle, .generation);

    slot := check_generation(table, locator, generation);
    return slot;
}
