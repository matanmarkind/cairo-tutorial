%builtins output pedersen range_check ecdsa

from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.cairo_builtins import (
    HashBuiltin, SignatureBuiltin)
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.dict import (
    DictAccess, dict_squash, dict_new, dict_update)
from starkware.cairo.common.math import assert_not_zero
from starkware.cairo.common.small_merkle_tree import small_merkle_tree

# The identifier that represents what we're voting for. This will appear in 
# the user's signature to distinguish between different polls.
const POLL_ID = 10018

# We can support up to 2**LOG_N_VOTERS voters.
const LOG_N_VOTERS = 10

struct VoteInfo:
    # The ID of the voter.
    # ??? - Why do we need member? If we add other types of things to structs, we can
    # Just at the keyword there and the default (like C++/Java) will be a member.
    # Or we can do Rust where a struct definition only has members and the impl
    # is a separate sections.
    member voter_id : felt
    # The voter's public key.
    member pub_key : felt
    # The vote (0 or 1).
    member vote : felt
    # The ECDSA signature (r and s).
    member r : felt
    member s : felt
end

struct VotingState:
    # The number of "Yes" votes.
    member n_yes_votes : felt
    # The number of "No" votes.
    member n_no_votes : felt
    # Start and end pointers to a DictAccess array with the changes to the
    # public key Merkle tree.
    member public_key_tree_start : DictAccess*
    member public_key_tree_end : DictAccess*
end

struct BatchOutput:
    member n_yes_votes : felt
    member n_no_votes : felt
    member public_key_root_before : felt
    member public_key_root_after : felt
end

func init_voting_state() -> (state : VotingState):
    alloc_locals
    local state : VotingState

    state.n_yes_votes = 0
    state.n_no_votes = 0

    # Create the implicit argument used to build `dict_new`.
    %{
        public_keys = [
            int(pub_key, 16)
            for pub_key in program_input['public_keys']]
        initial_dict = dict(enumerate(public_keys))
    %}
    let (dict : DictAccess*) = dict_new()

    state.public_key_tree_start = dict
    state.public_key_tree_end = dict

    return (state=state)
end

func verify_vote_signature{
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*}(
        vote_info_ptr : VoteInfo*):
    let (message) = hash2{hash_ptr=pedersen_ptr}(
        x=POLL_ID, y=vote_info_ptr.vote)

    verify_ecdsa_signature(
        message=message,
        public_key=vote_info_ptr.pub_key,
        signature_r=vote_info_ptr.r,
        signature_s=vote_info_ptr.s)

    return ()
end

func process_vote{
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
        state : VotingState}(
        vote_info_ptr : VoteInfo*):
    alloc_locals

    # Verify that pub_key != 0.
    assert_not_zero(vote_info_ptr.pub_key)

    # Verify the signature's validity.
    verify_vote_signature(vote_info_ptr=vote_info_ptr)

    # Update the public key dict.
    let public_key_tree_end = state.public_key_tree_end
    dict_update{dict_ptr=public_key_tree_end}(
        key=vote_info_ptr.voter_id,
        prev_value=vote_info_ptr.pub_key,
        new_value=0)

    # Generate the new state.
    local new_state : VotingState
    new_state.public_key_tree_start = (
        state.public_key_tree_start)
    new_state.public_key_tree_end = (
        public_key_tree_end)

    # Update the counters.
    tempvar vote = vote_info_ptr.vote
    if vote == 0:
        # Vote "No".
        new_state.n_yes_votes = state.n_yes_votes
        new_state.n_no_votes = state.n_no_votes + 1
    else:
        # Vote "Yes". Make sure that in this case vote=1.
        vote = 1
        new_state.n_yes_votes = state.n_yes_votes + 1
        new_state.n_no_votes = state.n_no_votes
    end

    # Update the state.
    # 
    # By updating where the implicit param points, you cause the captured value
    # to point to the new value. This means that implicit params have side
    # effects.
    let state = new_state
    return ()
end

func process_votes{
        pedersen_ptr : HashBuiltin*,
        ecdsa_ptr : SignatureBuiltin*,
        state : VotingState}(
        votes : VoteInfo*,
        n_votes : felt):
    if n_votes == 0:
        return ()
    end

    # Implicit params with the same name as a variable in scope are captured
    # automatically.
    process_vote(vote_info_ptr=votes)

    process_votes(
        votes=votes + VoteInfo.SIZE, n_votes=n_votes-1)

    return ()
end

# Returns a list of VoteInfo instances representing the claimed votes. The
# validity of the returned data is not guaranteed and must be verified by the
# caller.
func get_claimed_votes() -> (votes : VoteInfo*, num_votes : felt):
    alloc_locals
    local num_votes
    let (votes : VoteInfo*) = alloc()
    %{
        ids.num_votes = len(program_input['votes'])
        public_keys = [
            int(pub_key, 16)
            for pub_key in program_input['public_keys']]

        for i, vote in enumerate(program_input['votes']):
            # Get the address of the i-th vote.
            base_addr = \
                ids.votes.address_ + ids.VoteInfo.SIZE * i
            memory[base_addr + ids.VoteInfo.voter_id] = \
                vote['voter_id']
            memory[base_addr + ids.VoteInfo.pub_key] = \
                public_keys[vote['voter_id']]
            memory[base_addr + ids.VoteInfo.vote] = \
                vote['vote']
            memory[base_addr + ids.VoteInfo.r] = \
                int(vote['r'], 16)
            memory[base_addr + ids.VoteInfo.s] = \
                int(vote['s'], 16)
    %}

    return (votes=votes, num_votes=num_votes)
end

func main{
        output_ptr : felt*,
        pedersen_ptr : HashBuiltin*,
        range_check_ptr,
        ecdsa_ptr : SignatureBuiltin*}():
    alloc_locals

    let output = cast(output_ptr, BatchOutput*)
    let output_ptr = output_ptr + BatchOutput.SIZE

    let (votes, n_votes) = get_claimed_votes()
    %{
        votes = memory.get_range(
            ids.votes.address_, ids.n_votes * ids.VoteInfo.SIZE)
        print(f'{votes=}')
        print()
    %}

    let (state) = init_voting_state()
    %{
        print(f'{ids.state.n_yes_votes=}    {ids.state.n_no_votes=}')
        start = ids.state.public_key_tree_start.address_
        end = ids.state.public_key_tree_end.address_
        pub_key_tree = memory.get_range(
            ids.state.public_key_tree_start.address_, end - start)
        print(f'{pub_key_tree=}')
        print()
    %}

    process_votes{state=state}(votes=votes, n_votes=n_votes)
    %{
        print(f'{ids.state.n_yes_votes=}    {ids.state.n_no_votes=}')
        start = ids.state.public_key_tree_start.address_
        end = ids.state.public_key_tree_end.address_
        pub_key_tree = memory.get_range(
            ids.state.public_key_tree_start.address_, end - start)
        print(f'{pub_key_tree=}')
    %}

    # Write the vote counts to the output.
    output.n_yes_votes = state.n_yes_votes
    output.n_no_votes = state.n_no_votes

    # Squash the dict.
    # ??? - What is the hint info that gets returned? Where is it used?
    let (squashed_dict_start, squashed_dict_end) = dict_squash(
        dict_accesses_start=state.public_key_tree_start,
        dict_accesses_end=state.public_key_tree_end)
    %{
        start = ids.squashed_dict_start.address_
        end = ids.squashed_dict_end.address_
        squashed_dict = memory.get_range(
            ids.squashed_dict_start.address_, end - start)
        print(f'{squashed_dict=}')
        print()
    %}

    # Compute the Merkle roots and write to output.
    # ??? Why is `root_before` for intpu2 the same as `root_after` for input?
    # I understand that conceptually it is because the list of public keys is
    # the same since we 0 them out after the votes, but how does that
    # percolate to `small_merkle_tree`?. When I print out squashed_dict above
    # It only shows an entry for ID of the voter. So does merkle tree
    # implicitly build a tree to depth `height` and then fill all the leaves
    # with 0, and then fills the leaves the at index dict.key with 
    # dict.{prev,next}_value?
    let (root_before, root_after) = small_merkle_tree{
        hash_ptr=pedersen_ptr}(
        squashed_dict_start=squashed_dict_start,
        squashed_dict_end=squashed_dict_end,
        height=LOG_N_VOTERS)
    output.public_key_root_before = root_before
    output.public_key_root_after = root_after

    return ()
end