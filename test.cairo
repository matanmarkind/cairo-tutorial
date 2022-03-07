%builtins output

from starkware.cairo.common.serialize import serialize_word
from starkware.cairo.common.alloc import alloc

func array_sum(arr : felt*, size) -> (sum):
    if size == 0:
        return (sum=0)
    end

    let (sum_of_rest) = array_sum(arr=arr+1, size=size-1)
    return (sum=[arr] + sum_of_rest)
end

func array_product(arr : felt*, size) -> (product):
    if size == 0:
        return (product=1)
    end

    const STEP=2
    let (product_of_rest) = array_product(arr=arr+STEP, size=size-STEP)
    return (product=[arr] * product_of_rest)
end

func main{output_ptr : felt*}():
    const ARRAY_SIZE = 4

    let (ptr) = alloc()

    assert [ptr] = 9
    assert [ptr + 1] = 16
    assert [ptr + 2] = 25
    assert [ptr + 3] = 1

    # let is evaluated lazily. It is a reference to an expression.
    let (product) = array_product(arr=ptr, size=ARRAY_SIZE)
    serialize_word(product)

    return ()
end