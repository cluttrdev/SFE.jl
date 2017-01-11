
using CMesh: Mesh, nodes, topology, entities
using CMesh.Topology: Segment, Triangle, Quadrilateral, Tetrahedron, Hexahedron

using ..Elements

export refelem, evalReferenceMaps, evalJacobianInverse, evalJacobianDeterminat

typealias Float AbstractFloat

"""

    refelem(m::Mesh)

Return a reference shape element for the mesh.
"""
refelem(m::Mesh{Segment})       = P1(1)
refelem(m::Mesh{Triangle})      = P1(2)
refelem(m::Mesh{Tetrahedron})   = P1(3)
refelem(m::Mesh{Quadrilateral}) = Q1(2)
refelem(m::Mesh{Hexahedron})    = Q1(3)

"""

    evalReferenceMaps{T<:Float}(m::Mesh, points::AbstractArray{T,2}, deriv::Integer=0)

  Evaluate for each mesh element its associated reference map
  at given local points on the reference domain.
"""
function evalReferenceMaps{T<:Float}(m::Mesh, points::AbstractArray{T,2}, deriv::Integer=0)
    nP, dimP = size(points)

    coords = nodes(m)
    nW = size(coords, 2)

    basis = evalBasis(refelem(m), points, deriv)
    nB, nP, nC, nD, nDD = size(basis, 1:5...)
    @assert nC == 1 "nC = $nC == 1"
    
    elems = entities(topology(m), dimP)
    nE = size(elems, 1)
    @assert nB == size(elems, 2)

    if deriv == 0
        @assert nD == 1
        R = zeros(T, nE, nP, nW)
    elseif deriv == 1
        @assert nD == dimP "nD = $nD == $dimP = dimP"
        R = zeros(T, nE, nP, nW, nD)
    elseif deriv == 2
        @assert nD == dimP "nD = $nD == $nDD = nDD"
        R = zeros(T, nE, nP, nW, nD, nDD)
    end

    fill_refmaps!(R, coords, elems, basis)

    return R
end

@noinline function fill_refmaps!{T<:Float}(R::AbstractArray{T,3}, nodes::Array{T,2},
                                           elems::Array{Int,2}, basis::Array{T,3})
    for iw = 1:size(R,3) # nW
        for ip = 1:size(R,2) # nP
            for ie = 1:size(R,1) # nE
                for ib = 1:size(basis,1) # nB
                    R[ie,ip,iw] += nodes[elems[ie,ib],iw] * basis[ib,ip,1]
                end
            end
        end
    end

    return nothing
end

@noinline function fill_refmaps!{T<:Float}(R::Array{T,4}, nodes::Array{T,2},
                                           elems::Array{Int,2}, basis::Array{T,4})
    for id = 1:size(R,4) # nD
        fill_refmaps!(view(R, :, :, :, id), nodes, elems, basis[:,:,:,id])
    end

    return nothing
end

@noinline function fill_refmaps!{T<:Float}(R::Array{T,5}, nodes::Array{T,2},
                                           elems::Array{Int,2}, basis::Array{T,5})
    for jd = 1:size(R,5) # nD
        for id = 1:size(R,4) # nD
            fill_refmaps!(view(R, :, :, :, id, jd), nodes, elems, basis[:,:,:,id,jd])
        end
    end

    return nothing
end

# @noinline function fill_refmaps!{T<:Float}(R::Array{T,4}, nodes::Array{T,2},
#                                            elems::Array{Int,2}, basis::Array{T,4})
#     for id = 1:size(R,4) # nD
#         for iw = 1:size(R,3) # nW
#             for ip = 1:size(R,2) # nP
#                 for ie = 1:size(R,1) # nE
#                     for ib = 1:size(basis,1) # nB
#                         R[ie,ip,iw,id] += nodes[elems[ie,ib],iw] * basis[ib,ip,1,id]
#                     end
#                 end
#             end
#         end
#     end
# end

# @noinline function fill_refmaps!{T<:Float}(R::Array{T,5}, nodes::Array{T,2},
#                                            elems::Array{Int,2}, basis::Array{T,5})
#     for jd = 1:size(R,5) # nD
#         for id = 1:size(R,4) # nD
#             for iw = 1:size(R,3) # nW
#                 for ip = 1:size(R,2) # nP
#                     for ie = 1:size(R,1) # nE
#                         for ib = 1:size(basis,1) # nB
#                             R[ie,ip,iw,id,jd] += nodes[elems[ie,ib],iw] * basis[ib,ip,1,id,jd]
#                         end
#                     end
#                 end
#             end
#         end
#     end
# end

"""

    evalJacobianInverse{T<:Float}(m::Mesh, points::AbstractArray{T,2})

  Compute the inverse of the jacobian of each reference map 
  evaluated in every given local point.
"""
function evalJacobianInverse{T<:Float}(m::Mesh, points::AbstractArray{T,2})
    jacs = evalReferenceMaps(m, points, 1)
    nE, nP, nW, nD = size(jacs)

    if (nW == nD) || (nD == 1)
        fill_JacsInv!(jacs)
    else
        error("Invalid shape of jacobians! (", nW, nD, ")")
    end

    return jacs
end

function fill_JacsInv!{T<:Float}(jacs::Array{T,4})
    issquare = (size(jacs,3) == size(jacs,4))
    for ip = 1:size(jacs,2) # nP
        for ie = 1:size(jacs,1) # nE
            jacs[ie,ip,:,:] = issquare ? inv(jacs[ie,ip,:,:]) : 1./jacs[ie,ip,:,:]
        end
    end
end

"""

    evalJacobianInverse{T<:Float}(m::Mesh, points::AbstractArray{T,2})

  Compute the determinant of the jacobian of each reference map 
  evaluated in every given local point.
"""
function evalJacobianDeterminat{T<:Float}(m::Mesh, points::AbstractArray{T,2})
    jacs = evalReferenceMaps(m, points, 1)
    nE, nP, nW, nD = size(jacs)

    D = zeros(eltype(jacs), nE, nP)
    fill_JacsDet!(D, jacs, Val{nW}, Val{nD})

    return D
end

function fill_JacsDet!{T<:Float}(D::Array{T,2}, jacs::Array{T,4}, ::Type{Val{2}}, ::Type{Val{1}})
    for ip = 1:size(D,2) # nP
        for ie = 1:size(D,1) # nE
            D[ie,ip] = sqrt(jacs[ie,ip,1,1]^2 + jacs[ie,ip,2,1]^2)
        end
    end
end

function fill_JacsDet!{T<:Float}(D::Array{T,2}, jacs::Array{T,4}, ::Type{Val{3}}, ::Type{Val{1}})
    for ip = 1:size(D,2) # nP
        for ie = 1:size(D,1) # nE
            D[ie,ip] = sqrt(jacs[ie,ip,1,1]^2 + jacs[ie,ip,2,1]^2 + jacs[ie,ip,3,1]^2)
        end
    end
end

function fill_JacsDet!{T<:Float}(D::Array{T,2}, jacs::Array{T,4}, ::Type{Val{2}}, ::Type{Val{2}})
    for ip = 1:size(D,2) # nP
        for ie = 1:size(D,1) # nE
            D[ie,ip] = jacs[ie,ip,1,1] * jacs[ie,ip,2,2] - jacs[ie,ip,2,1] * jacs[ie,ip,1,2]
        end
    end
end

function fill_JacsDet!{T<:Float}(D::Array{T,2}, jacs::Array{T,4}, ::Type{Val{3}}, ::Type{Val{2}})
    for ip = 1:size(D,2) # nP
        for ie = 1:size(D,1) # nE
            D[ie,ip] = sqrt((jacs[ie,ip,2,1] * jacs[ie,ip,3,2] - jacs[ie,ip,3,1] * jacs[ie,ip,2,2])^2
                            + (jacs[ie,ip,3,1] * jacs[ie,ip,1,2] - jacs[ie,ip,1,1] * jacs[ie,ip,3,2])^2
                            + (jacs[ie,ip,1,1] * jacs[ie,ip,2,2] - jacs[ie,ip,2,1] * jacs[ie,ip,1,2])^2)
        end
    end
end

function fill_JacsDet!{T<:Float}(D::Array{T,2}, jacs::Array{T,4}, ::Type{Val{3}}, ::Type{Val{3}})
    for ip = 1:size(D,2) # nP
        for ie = 1:size(D,1) # nE
            D[ie,ip] = jacs[ie,ip,1,1] * jacs[ie,ip,2,2] * jacs[ie,ip,3,3] +
                jacs[ie,ip,1,2] * jacs[ie,ip,2,3] * jacs[ie,ip,3,1] +
                jacs[ie,ip,1,3] * jacs[ie,ip,2,1] * jacs[ie,ip,3,2] -
                jacs[ie,ip,1,1] * jacs[ie,ip,2,3] * jacs[ie,ip,3,2] -
                jacs[ie,ip,1,2] * jacs[ie,ip,2,1] * jacs[ie,ip,3,3] -
                jacs[ie,ip,1,3] * jacs[ie,ip,2,2] * jacs[ie,ip,3,1]
        end
    end
end

# for compatibility
function evalTrafo{T<:Float}(m::Mesh, dPhi::AbstractArray{T,4})
    nE, nP, nW, nD = size(dPhi)
    D = zeros(T, nE, nP)
    fill_JacsDet!(D, dPhi, Val{nW}, Val{nD})
    return D
end

function evalTrafoPair{T<:Float}(m::Mesh, points::AbstractArray{T,2})
    DPhi = evalReferenceMap(m, points, 1);
    trafo = evalTrafo(m, DPhi);
    return (DPhi, trafo)
end

function evalTrafoTriple{T<:Float}(m::Mesh, points::AbstractArray{T,2})
    R = evalReferenceMap(m, points, 1); # nExnPxnWx[...]
    if m.dimension == 1
        det = R; RInv = 1;
    elseif m.dimension == 2
        det = R[:,:,1,1].*R[:,:,2,2] - R[:,:,1,2].*R[:,:,2,1];
        RInv = -R;
        RInv[:,:,1,1] = R[:,:,2,2];
        RInv[:,:,2,2] = R[:,:,1,1];
    elseif m.dimension == 3
        det = R[:,:,1,1].*R[:,:,2,2].*R[:,:,3,3] +
            R[:,:,1,2].*R[:,:,2,3].*R[:,:,3,1] +
            R[:,:,1,3].*R[:,:,2,1].*R[:,:,3,2] -
            R[:,:,1,1].*R[:,:,2,3].*R[:,:,3,2] -
            R[:,:,1,2].*R[:,:,2,1].*R[:,:,3,3] -
            R[:,:,1,3].*R[:,:,2,2].*R[:,:,3,1];
        RInv[:,:,1,1] = R[:,:,2,2].*R[:,:,3,3] - R[:,:,2,3].*R[:,:,3,2];
        RInv[:,:,2,1] = -(R[:,:,2,1].*R[:,:,3,3] - R[:,:,3,1].*R[:,:,2,3]);
        RInv[:,:,3,1] = R[:,:,2,1].*R[:,:,3,2] - R[:,:,2,2].*R[:,:,3,1];
        RInv[:,:,1,2] = -(R[:,:,1,2].*R[:,:,3,3] - R[:,:,1,3].*R[:,:,3,2]);
        RInv[:,:,2,2] = R[:,:,1,1].*R[:,:,3,3] - R[:,:,1,3].*R[:,:,3,1];
        RInv[:,:,3,2] = -(R[:,:,1,1].*R[:,:,3,2] - R[:,:,1,2].*R[:,:,3,1]);
        RInv[:,:,1,3] = R[:,:,1,2].*R[:,:,2,3] - R[:,:,1,3].*R[:,:,2,2];
        RInv[:,:,2,3] = -(R[:,:,1,1].*R[:,:,2,3] - R[:,:,1,3].*R[:,:,2,1]);
        RInv[:,:,3,3] = R[:,:,1,1].*R[:,:,2,2] - R[:,:,1,2].*R[:,:,2,1];
    else
        error("Non supported dimension")
    end
    RInv = broadcast(/, RInv, det);
    return (R, RInv, det)
end