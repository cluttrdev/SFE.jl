__precompile__()

module Spaces

import ..Elements: nDoF

using ..Elements
using ..Meshes

export AbstractFESpace, FESpace
export mesh, element, dofMap, nDoF, dofIndices, dofMask, extractDoFs, interpolate

abstract AbstractFESpace

#--------------#
# Type FESpace #
#--------------#
type FESpace{M<:AbstractMesh, E<:AbstractElement} <: AbstractFESpace
    mesh :: M
    element :: E
    freeDOF :: Array{Bool, 1}
    shift :: Function
end

function FESpace{M<:AbstractMesh, E<:AbstractElement}(m::M, el::E,
                                                      bfnc::Function=x->trues(size(x,1)),
                                                      shift::Function=x->zeros(size(x,1)))
    #freeDOF = !getBoundaryDOFs(m, bfnc)
    freeDOF = []

    return FESpace{M,E}(m, el, freeDOF, shift)
end

# Associated Methods
# -------------------
@inline mesh(fes::FESpace) = getfield(fes, :mesh)
@inline element(fes::FESpace) = getfield(fes, :element)

"""

    dofMap(fes::FESpace, d::Integer)

  Return the degrees of freedom mapping that connects the global mesh
  entities of topological dimension `d` to the local reference element.

  Establishes the connection between the local and global degrees of freedom
  via a connectivity array `C` where `C[i,j] = k` connects the `i`-th
  local basis function  on the reference element to the `k`-th global basis 
  function on the `j`-th element.
"""
function dofMap(fes::FESpace, d::Integer)
    dofTuple = Elements.dofTuple(fes.element)
    dofPerDim = nDoF(fes.element, d)
    nEntities = [getNumber(fes.mesh.topology, dd) for dd = 0:d]
    dofsNeeded = [nEntities[dd+1] * dofTuple[dd+1] for dd = 0:d]
    ndofs = [0, cumsum(dofsNeeded)...]
    dofs = [reshape(ndofs[i]+1:ndofs[i+1], dofTuple[i], nEntities[i]) for i = 1:d+1]

    M = [zeros(Int, dofPerDim[i], nEntities[d+1]) for i = 1:d+1]

    if Meshes.Topology.USE_X
        for dd = 0:d-1
            d_dd = getConnectivity(fes.mesh.topology, d, dd)
            for i = 1:size(d_dd, 1)
                for j = 1:size(d_dd, 2)
                    r = (j-1)*dofTuple[dd+1]+1 : j*dofTuple[dd+1]
                    M[dd+1][r,i] = dofs[dd+1][:,d_dd[i,j]]
                end
            end
        end
    else
        # first iterate over subdims
        for dd = 0:d-1
            for (i, d_dd_i) in enumerate(getConnectivity(fes.mesh.topology, d, dd))
                for (j, d_dd_ij) in enumerate(d_dd_i)
                    r = (j-1)*dofTuple[dd+1]+1 : j*dofTuple[dd+1]
                    M[dd+1][r,i] = dofs[dd+1][:,d_dd_ij]
                end
            end
        end
    end

    # set dofs of query dim
    M[d+1] = dofs[d+1]

    return vcat(M...)
end

"""

    nDoF(fes::FESpace)

  Return the total number of degrees of freedom for the
  finite element space `fes`.
"""
function nDoF(fes::FESpace)
    #return maxabs(getDOFMap(fes, fes.mesh.dimension))
    return maxabs(dofMap(fes, fes.mesh.dimension))
end

"""

    dofIndices(fes::FESpace, d::Integer)

  Return the indices of the degrees of freedom for the finite
  element space `fes` associated with the mesh entities of 
  topological dimension `d`.
"""
function dofIndices(fes::FESpace, d::Integer)
    dofMap = dofMap(fes, d)
    return sort!(unique(dofMap))
end

"""

    dofMask(fes::FESpace, d::Integer)

  Return a boolean mask specifying the degrees of freedom
  for the finite element space `fes` associated with the 
  mesh entities of topological dimension `d`.
"""
function dofMask(fes::FESpace, d::Integer)
    mask = zeros(Bool, nDoF(fes))
    for i in dofIndices(fes, d)
        mask[i] = true
    end
    return mask
end
extractDoF(fes::FESpace, d::Integer) = dofMask(fes, d)

function interpolate(m::Mesh, el::Element, f::Function)
    @assert isnodal(el)

    d = dim(el)
    p = order(el)

    v = getNodes(m)
    e = p > 1 ? evalReferenceMap(m, linspace(0,1,p+1)[2:end-1]) : zeros(0,d)
    #i = (p > 2 && d > 1) ? evalReferenceMap(m, lagrangeNodesP(d,p)[p*(d+1):,:]) : zeros(0,d)

    n = vcat(v, e, i)

    return f(n)
end
interpolate(fes::FESpace, f::Function) = interpolate(fes.mesh, fes.element, f)

end # of module Spaces