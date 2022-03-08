%builtins range_check

from starkware.cairo.common.squash_dict import squash_dict
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.alloc import alloc

struct KeyValue:
    member key : felt
    member value : felt
end

# Builds a DictAccess list for the computation of the cumulative
# sum for each key.
func build_dict(list : KeyValue*, size, dict : DictAccess*) -> (
        dict : DictAccess*):
    alloc_locals

    if size == 0:
        return (dict=dict)
    end

    local sum
    local prev

    %{
        # Populate ids.dict.prev_value using cumulative_sums...
        # Add list.value to cumulative_sums[list.key]...
        ids.prev = cumulative_sums.get(ids.list.key, 0)
        ids.sum = ids.prev + ids.list.value
        cumulative_sums[ids.list.key] = ids.sum
    %}

    assert sum = list.value + prev
    # ??? - assert is how you assign?
    # This adds a constraint. If `dict.key` had no value we are free to fill this
    # constraint by setting it equal to `list.key`. Otherwise, the constraint is
    # only valid if `dict.key` is already equal to `list.key` (aka an assertion). 
    assert dict.key = list.key  # list.key adds a deref op, so multiple ops.
    # `assert` means that this compiles to multiple lines of CAIRO (adding 
    # another line to the trace).
    # 
    # This line doesn't need an assert because CAIRO has a single opcode for
    # `deref + assign`. The line above though needs to dereference both dict and
    # list, and there is no opcode for `deref + deref + assign`
    dict.prev_value = prev
    dict.new_value = sum

    return build_dict(
        list=list + KeyValue.SIZE,
        size=size - KeyValue.SIZE,
        dict=dict + DictAccess.SIZE)
end

# Verifies that the initial values were 0, and writes the final
# values to result.
func verify_and_output_squashed_dict(
        squashed_dict : DictAccess*,
        squashed_dict_end : DictAccess*, result : KeyValue*) -> (
        result : KeyValue*):
    if squashed_dict_end - squashed_dict == 0:
        return (result=result)
    end

    # ??? - It seems to me that we are using the same syntax to do very 
    # different activities.
    # Assertion
    assert squashed_dict.prev_value = 0
    # Assignment
    assert result.key = squashed_dict.key
    assert result.value = squashed_dict.new_value

    return verify_and_output_squashed_dict(
        squashed_dict=squashed_dict + DictAccess.SIZE,
        squashed_dict_end=squashed_dict_end,
        result=result + KeyValue.SIZE)
end

# Given a list of KeyValue, sums the values, grouped by key,
# and returns a list of pairs (key, sum_of_values).
# Note that size is the total number of felts in the list, not the number of
# KeyValues. This is the standard in Cairo.
func sum_by_key{range_check_ptr}(list : KeyValue*, size) -> (
        result : KeyValue*, result_size):
    alloc_locals

    %{
        # Initialize cumulative_sums with an empty dictionary. This variable 
        # will be used by ``build_dict`` to hold the current sum for each key.
        cumulative_sums = {}
    %}

    let (local dict : DictAccess*) = alloc()
    let (dict_end : DictAccess*) = build_dict(list=list, size=size, dict=dict)

    %{
        print(f'{cumulative_sums=}')
        dict_size = ids.dict_end.address_ - ids.dict.address_
        print(f'{dict_size=}')
        built_dict = memory.get_range(ids.dict.address_, dict_size)
        print(f'{built_dict=}')
    %}

    let (local squashed_dict : DictAccess*) = alloc()
    let (squashed_dict_end : DictAccess*) = squash_dict(
        dict_accesses=dict,
        dict_accesses_end=dict_end,
        squashed_dict=squashed_dict)

    %{
        squashed_size = ids.squashed_dict_end.address_ - ids.squashed_dict.address_
        print(f'{squashed_size=}')
        squashed_dict = memory.get_range(ids.squashed_dict.address_, squashed_size)
        print(f'{squashed_dict=}')
    %}

    let (local result : KeyValue*) = alloc()
    verify_and_output_squashed_dict(
        squashed_dict=squashed_dict,
        squashed_dict_end=squashed_dict_end,
        result=result)
    
    local num_results = (squashed_dict_end - squashed_dict) / DictAccess.SIZE
    return (result=result, result_size=num_results * KeyValue.SIZE)
end

func main{range_check_ptr}():
    alloc_locals

    local input_list : KeyValue*
    local input_list_size : felt

    %{
        # This statement is doing a couple things:
        # segment.add is the hint version of alloc. The double '=' is a double
        # assignment, both ids.input_list & kvl now point to `segment.add`.
        ids.input_list = kvl = segments.add()
        origin = ((3, 5), (1, 10), (3, 1), (3, 8), (1, 20))
        # size refers to the number of felts, not KeyValues.
        ids.input_list_size = len(origin) * 2
        for i, (k, v) in enumerate(origin):
            memory[kvl + 2*i] = k
            memory[kvl + 2*i + 1] = v
    %}

    %{
        input_list = memory.get_range(ids.input_list.address_, ids.input_list_size)
        print(f'{input_list=}')
    %}

    let (local sum_list : KeyValue*, local sum_list_size) = sum_by_key(
        list=input_list, size=input_list_size)

    %{
        sum_list = memory.get_range(ids.sum_list.address_, ids.sum_list_size)
        print(f'{sum_list=}')
        print()
    %}

    return ()
end