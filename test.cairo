func array_even_product(arr: felt*, size) -> (product):
    if size == 1:
        return (product = [arr])
    end
    if size == 0:
        return (product=1)
    end

    let (product_of_rest) = array_even_product(arr=arr+2, size=size-2)
    return (product=[arr] * product_of_rest)
end