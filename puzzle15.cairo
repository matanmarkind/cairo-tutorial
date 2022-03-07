%builtins output range_check

from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.alloc import alloc

struct Location:
    member row : felt
    member col : felt
end

func verify_valid_location(loc : Location*):
    # tempvar is evaluated eagerly and can be revoked easily.
    tempvar row = loc.row
    assert row * (row-1) * (row-2) * (row-3) = 0

    tempvar col = loc.col
    assert col * (col-1) * (col-2) * (col-3) = 0

    return ()
end

func verify_adjacent_locations(
        loc0: Location*, loc1: Location*):
    alloc_locals
    local row_diff = loc0.row - loc1.row
    local col_diff = loc0.col - loc1.col
    
    if row_diff == 0:
        assert col_diff * col_diff = 1
        return ()
    else:
        assert col_diff = 0
        assert row_diff * row_diff = 1
        return ()
    end
end

func verify_location_list(loc_list: Location*, n_steps):
    # len(loc_list) == n_steps + 1
    verify_valid_location(loc=loc_list)

    if n_steps == 0:
        assert loc_list.row = 3
        assert loc_list.col = 3
        return ()
    end

    verify_adjacent_locations(
        loc0=loc_list, loc1=loc_list+Location.SIZE)

    verify_location_list(
        loc_list=loc_list+Location.SIZE, n_steps=n_steps-1)

    return ()
end

# empty_tile_locations - list of locations that the empty tile visits.
# moved_tile_list - Identity of the tiles moved at each step.
# n_steps - number of moves.
# dict - multimap from a tile to it's movement. Each step is the inverse of
#   of the moves represented by `loc_list`. {tile : [(prev, new)]}.
func build_dict(
        empty_tile_locations : Location*, moved_tiles : felt*, n_steps,
        tile_to_moves : DictAccess*) -> (tile_to_moves : DictAccess*):
    if n_steps == 0:
        return (tile_to_moves=tile_to_moves)
    end

    # Set the key to the current tile being moved.
    assert tile_to_moves.key = [moved_tiles]
    
    let empty_next_loc : Location* = empty_tile_locations + Location.SIZE
    # The current tile moves from the empty ones next locaiton to the empty
    # ones previous location.
    assert tile_to_moves.prev_value = 4 * empty_next_loc.row + empty_next_loc.col
    assert tile_to_moves.new_value = 4 * empty_tile_locations.row + empty_tile_locations.col

    return build_dict(
        empty_tile_locations=empty_next_loc,
        moved_tiles=moved_tiles + 1,
        n_steps=n_steps - 1,
        tile_to_moves=tile_to_moves + DictAccess.SIZE)
end

# Pass in the head of `dict`. Returns end of `dict`.
# Fills dict with locations for each tile
func finalize_state(dict: DictAccess*, idx) -> (
        dict: DictAccess*):
    if idx == 0:
        return (dict=dict)
    end

    assert dict.key = idx
    assert dict.prev_value = idx-1
    assert dict.new_value = idx - 1

    return finalize_state(
        dict=dict + DictAccess.SIZE, idx=idx-1)
end

func output_initial_values{output_ptr: felt*}(
        squashed_dict: DictAccess*, n_steps):
    if n_steps == 0:
        return ()
    end

    serialize_word(squashed_dict.prev_value)

    return output_initial_values(
        squashed_dict=squashed_dict + DictAccess.SIZE, n_steps=n_steps-1)
end

func check_solution{output_ptr: felt*, range_check_ptr}(
        empty_tile_locations: Location*, moved_tiles: felt*, n_steps):
    alloc_locals

    verify_location_list(loc_list=empty_tile_locations, n_steps=n_steps)

    # What is this `let local` terminology?
    let (local squashed_dict: DictAccess*) = alloc()
    let (local tile_to_moves_start: DictAccess*) = alloc()

    let (tile_to_moves_end) = build_dict(
        empty_tile_locations=empty_tile_locations,
        moved_tiles=moved_tiles,
        n_steps=n_steps,
        tile_to_moves=tile_to_moves_start)

    # We are growing the DictAccess. `alloc` creates a list that is "infinitely"
    # extendable.
    let (tile_to_moves_end) = finalize_state(dict=tile_to_moves_end, idx=15)

    let (squashed_dict_end : DictAccess*) = squash_dict(
        dict_accesses=tile_to_moves_start,
        dict_accesses_end=tile_to_moves_end,
        squashed_dict=squashed_dict)
    assert squashed_dict_end - squashed_dict = 15 * DictAccess.SIZE
    
    # ??? - Tutorial says commenting this out should fail to compile.
    # Update tutorial, this was fixed in cairo.
    # local range_check_ptr = range_check_ptr

    # Store range_check_ptr in a local variable to make it
    # accessible after the call to `output_initial_values`.
    output_initial_values(squashed_dict=squashed_dict, n_steps=15)

    serialize_word(4 * empty_tile_locations.row + empty_tile_locations.col)

    serialize_word(n_steps)

    return ()
end

func main{output_ptr: felt*, range_check_ptr}():
    alloc_locals

    local empty_tile_locations : Location*
    local moved_tiles : felt*
    local n_steps

    %{
        locations = program_input['empty_tile_locations']
        # This is multiple assignment. This points `ids.empty_tile_locations`
        # to the relevant segment. Note that we can add onto it indefinitely.
        ids.empty_tile_locations = empty_tile_locations = segments.add()
        for i, val in enumerate(locations):
            # `memory` is a reserved term for doing pointer dereferencing from 
            # hints. We can now reach each each field (felt) in the memory 
            # allocated for `empty_tile_locations`, and set each one of them.
            # Note that we aren't building Location directly, rather we are
            # individually setting the fields, which in the raw CAIRO, will be
            # interpreted as `Location`s.
            memory[empty_tile_locations + i] = val

        tiles = program_input['moved_tiles']
        ids.moved_tiles = moved_tiles = segments.add()
        for i, val in enumerate(tiles):
            memory[moved_tiles + i] = val

        n_steps = len(tiles)

        assert len(locations) == 2 * (len(tiles) + 1)
    %}

    # Since the tuple elements are next to each other, we can use the
    # address of loc_tuple as a pointer to the 5 locations.
    check_solution(
        empty_tile_locations=empty_tile_locations,
        moved_tiles=moved_tiles,
        n_steps=4)
    
    return ()
end