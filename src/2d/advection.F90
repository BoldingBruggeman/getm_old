#include "cppdefs.h"
!-----------------------------------------------------------------------
!BOP
!
! !MODULE:  2D advection
!
! !INTERFACE:
   module advection
!
! !DESCRIPTION:
!
!  This module does lateral advection of scalars. It follows the same
!  convention as the other modules in 'getm'. The module is initialised
!  by calling 'init\_advection()'. In the time-loop 'do\_advection()' is
!  called. 'do\_advection' is a wrapper routine which - dependent on the
!  actual advection scheme chosen - makes calls to the appropriate
!  subroutines, which may be done as one-step or multiple-step schemes.
!  The actual subroutines are coded in external FORTRAN files.
!  New advection schemes are easily implemented - at least from a program
!  point of view - since only this module needs to be changed.
!  Additional work arrays can easily be added following the stencil given
!  below. To add a new advection scheme three things must be done:
!
!  \begin{enumerate}
!  \item define
!  a unique constant to identify the scheme (see e.g.\ {\tt UPSTREAM}
!  and {\tt TVD})
!  \item adopt the {\tt select case} in {\tt do\_advection} and
!  \item  write the actual subroutine.
!  \end{enumerate}
!
! !USES:
   use domain, only: imin,imax,jmin,jmax
   IMPLICIT NONE

   private
!
! !PUBLIC DATA MEMBERS:
   public init_advection,do_advection,print_adv_settings
   public adv_split_u,adv_split_v,adv_upstream_2dh,adv_arakawa_j7_2dh,adv_fct_2dh
   public adv_tvd_limiter

   type, public :: t_adv_grid
      logical,dimension(:,:),pointer :: mask_uflux,mask_vflux,mask_xflux
      logical,dimension(:,:),pointer :: mask_uupdate,mask_vupdate
      logical,dimension(:,:),pointer :: mask_finalise
      integer,dimension(:,:),pointer :: az
#if defined(SPHERICAL) || defined(CURVILINEAR)
      REALTYPE,dimension(:,:),pointer :: dxu,dyu,dxv,dyv,arcd1
#endif
   end type t_adv_grid

   type(t_adv_grid),public,target :: adv_gridH,adv_gridU,adv_gridV

   integer,public,parameter           :: NOSPLIT=0,FULLSPLIT=1,HALFSPLIT=2
   character(len=64),public,parameter :: adv_splits(0:2) = &
                  (/"no split: one 2D uv step          ",  &
                    "full step splitting: u + v        ",  &
                    "half step splitting: u/2 + v + u/2"/)
   integer,public,parameter           :: NOADV=0,UPSTREAM=1,UPSTREAM_2DH=2
   integer,public,parameter           :: P2=3,SUPERBEE=4,MUSCL=5,P2_PDM=6
   integer,public,parameter           :: J7=7,FCT=8,P2_2DH=9
   character(len=64),public,parameter :: adv_schemes(0:9) = &
      (/"advection disabled                             ",  &
        "upstream advection (first-order, monotone)     ",  &
        "2DH-upstream advection with forced monotonicity",  &
        "P2 advection (third-order, non-monotone)       ",  &
        "TVD-Superbee advection (second-order, monotone)",  &
        "TVD-MUSCL advection (second-order, monotone)   ",  &
        "TVD-P2-PDM advection (third-order, monotone)   ",  &
        "2DH-J7 advection (Arakawa and Lamb, 1977)      ",  &
        "2DH-FCT advection                              ",  &
        "2DH-P2 advection                               "/)
   integer,public,parameter           :: NOSPLIT_NOFINALISE=0
   integer,public,parameter           :: NOSPLIT_FINALISE=1
   integer,public,parameter           :: SPLIT_UPDATE=2
!
! !LOCAL VARIABLES:
#ifdef STATIC
   logical,dimension(E2DFIELD),target         :: mask_updateH
   logical,dimension(E2DFIELD),target         :: mask_uflux,mask_vflux,mask_xflux
   logical,dimension(E2DFIELD),target         :: mask_uupdateU,mask_vupdateV
   REALTYPE,dimension(E2DFIELD)               :: Di,adv
#else
   logical,dimension(:,:),allocatable,target  :: mask_updateH
   logical,dimension(:,:),allocatable,target  :: mask_uflux,mask_vflux,mask_xflux
   logical,dimension(:,:),allocatable,target  :: mask_uupdateU,mask_vupdateV
   REALTYPE,dimension(:,:),allocatable        :: Di,adv
#endif
#ifndef _POINTER_REMAP_
   logical,dimension(:,:),allocatable,target  :: mask_ufluxU,mask_xfluxU,mask_xfluxV
   REALTYPE,dimension(:,:),allocatable,target :: dxuU,dyuU
#endif
!
! !REVISION HISTORY:
!  Original author(s): Knut Klingbeil
!EOP
!-----------------------------------------------------------------------

   interface
      subroutine adv_split_u(dt,f,Di,adv,U,Do,DU,                 &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                             dxu,dyu,arcd1,                       &
#endif
                             splitfac,scheme,action,AH,           &
                             mask_flux,mask_update,mask_finalise)
         use domain, only: imin,imax,jmin,jmax
         IMPLICIT NONE
         REALTYPE,intent(in)                             :: dt,splitfac,AH
         REALTYPE,dimension(E2DFIELD),intent(in)         :: U,Do,DU
#if defined(SPHERICAL) || defined(CURVILINEAR)
         REALTYPE,dimension(:,:),pointer,intent(in)      :: dxu,dyu
         REALTYPE,dimension(E2DFIELD),intent(in)         :: arcd1
#endif
         integer,intent(in)                              :: scheme,action
         logical,dimension(:,:),pointer,intent(in)       :: mask_flux
         logical,dimension(E2DFIELD),intent(in)          :: mask_update
         logical,dimension(E2DFIELD),intent(in),optional :: mask_finalise
         REALTYPE,dimension(E2DFIELD),intent(inout)      :: f,Di,adv
      end subroutine adv_split_u

      subroutine adv_split_v(dt,f,Di,adv,V,Do,DV,                 &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                             dxv,dyv,arcd1,                       &
#endif
                             splitfac,scheme,action,AH,           &
                             mask_flux,mask_update,mask_finalise)
         use domain, only: imin,imax,jmin,jmax
         IMPLICIT NONE
         REALTYPE,intent(in)                             :: dt,splitfac,AH
         REALTYPE,dimension(E2DFIELD),intent(in)         :: V,Do,DV
#if defined(SPHERICAL) || defined(CURVILINEAR)
         REALTYPE,dimension(_IRANGE_HALO_,_JRANGE_HALO_-1),intent(in) :: dxv,dyv
         REALTYPE,dimension(E2DFIELD),intent(in)         :: arcd1
#endif
         integer,intent(in)                              :: scheme,action
         logical,dimension(_IRANGE_HALO_,_JRANGE_HALO_-1),intent(in) :: mask_flux
         logical,dimension(E2DFIELD),intent(in)          :: mask_update
         logical,dimension(E2DFIELD),intent(in),optional :: mask_finalise
         REALTYPE,dimension(E2DFIELD),intent(inout)      :: f,Di,adv
      end subroutine adv_split_v

      subroutine adv_arakawa_j7_2dh(dt,f,Di,adv,U,V,Do,Dn,DU,DV,      &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                    dxv,dyu,dxu,dyv,arcd1,            &
#endif
                                    action,AH,az,                     &
                                    mask_uflux,mask_vflux,mask_xflux)
         use domain, only: imin,imax,jmin,jmax
         IMPLICIT NONE
         REALTYPE,intent(in)                        :: dt,AH
         REALTYPE,dimension(E2DFIELD),intent(in)    :: U,V,Do,Dn,DU,DV
#if defined(SPHERICAL) || defined(CURVILINEAR)
         REALTYPE,dimension(:,:),pointer,intent(in) :: dxu,dyu
         REALTYPE,dimension(_IRANGE_HALO_,_JRANGE_HALO_-1),intent(in) :: dxv,dyv
         REALTYPE,dimension(E2DFIELD),intent(in)    :: arcd1
#endif
         integer,intent(in)                         :: action
         integer,dimension(E2DFIELD),intent(in)     :: az
         logical,dimension(:,:),pointer,intent(in)  :: mask_uflux,mask_xflux
         logical,dimension(_IRANGE_HALO_,_JRANGE_HALO_-1),intent(in) :: mask_vflux
         REALTYPE,dimension(E2DFIELD),intent(inout) :: f,Di,adv
      end subroutine adv_arakawa_j7_2dh

      subroutine adv_upstream_2dh(dt,f,Di,adv,U,V,Do,Dn,DU,DV, &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                  dxv,dyu,dxu,dyv,arcd1,       &
#endif
                                  action,AH,az)
         use domain, only: imin,imax,jmin,jmax
         IMPLICIT NONE
         REALTYPE,intent(in)                        :: dt,AH
         REALTYPE,dimension(E2DFIELD),intent(in)    :: U,V,Do,Dn,DU,DV
#if defined(SPHERICAL) || defined(CURVILINEAR)
         REALTYPE,dimension(:,:),pointer,intent(in) :: dxu,dyu
         REALTYPE,dimension(_IRANGE_HALO_,_JRANGE_HALO_-1),intent(in) :: dxv,dyv
         REALTYPE,dimension(E2DFIELD),intent(in)    :: arcd1
#endif
         integer,intent(in)                         :: action
         integer,dimension(E2DFIELD),intent(in)     :: az
         REALTYPE,dimension(E2DFIELD),intent(inout) :: f,Di,adv
      end subroutine adv_upstream_2dh

      subroutine adv_fct_2dh(fct,dt,f,Di,adv,U,V,Do,Dn,DU,DV, &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                             dxv,dyu,dxu,dyv,arcd1,           &
#endif
                             action,AH,az,                    &
                             mask_uflux,mask_vflux)
         use domain, only: imin,imax,jmin,jmax
         IMPLICIT NONE
         logical,intent(in)                         :: fct
         REALTYPE,intent(in)                        :: dt,AH
         REALTYPE,dimension(E2DFIELD),intent(in)    :: U,V,Do,Dn,DU,DV
#if defined(SPHERICAL) || defined(CURVILINEAR)
         REALTYPE,dimension(:,:),pointer,intent(in) :: dxu,dyu
         REALTYPE,dimension(_IRANGE_HALO_,_JRANGE_HALO_-1),intent(in) :: dxv,dyv
         REALTYPE,dimension(E2DFIELD),intent(in)    :: arcd1
#endif
         integer,intent(in)                         :: action
         integer,dimension(E2DFIELD),intent(in)     :: az
         logical,dimension(:,:),pointer,intent(in)  :: mask_uflux
         logical,dimension(_IRANGE_HALO_,_JRANGE_HALO_-1),intent(in) :: mask_vflux
         REALTYPE,dimension(E2DFIELD),intent(inout) :: f,Di,adv
      end subroutine adv_fct_2dh

      REALTYPE function adv_tvd_limiter(scheme,cfl,fuu,fu,fd)
         IMPLICIT NONE
         integer,intent(in)  :: scheme
         REALTYPE,intent(in) :: cfl,fuu,fu,fd
      end function adv_tvd_limiter

   end interface

   contains

!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE:  init_advection
!
! !INTERFACE:
   subroutine init_advection()
!
! !DESCRIPTION:
!
! Allocates memory and sets up masks and lateral grid increments.
!
! !USES:
   use domain, only: az,au,av,ax
#if defined(SPHERICAL) || defined(CURVILINEAR)
   use domain, only: dxc,dyc,arcd1,dxu,dyu,arud1,dxv,dyv,arvd1,dxx,dyx
#endif
   IMPLICIT NONE
!
! !LOCAL VARIABLES:
   integer :: rc
!EOP
!-------------------------------------------------------------------------
!BOC
#ifdef DEBUG
   integer, save :: Ncall = 0
   Ncall = Ncall+1
   write(debug,*) 'init_advection() # ',Ncall
#endif

   LEVEL2 'init_advection'

#ifndef STATIC
   allocate(mask_updateH(E2DFIELD),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (mask_updateH)'

   allocate(mask_uflux(E2DFIELD),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (mask_uflux)'

   allocate(mask_vflux(E2DFIELD),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (mask_vflux)'

   allocate(mask_xflux(E2DFIELD),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (mask_xflux)'

   allocate(mask_uupdateU(E2DFIELD),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (mask_uupdateU)'

   allocate(mask_vupdateV(E2DFIELD),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (mask_vupdateV)'

   allocate(Di(E2DFIELD),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (Di)'

   allocate(adv(E2DFIELD),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (adv)'
#endif

   mask_updateH  = (az.eq.1)
   mask_uflux    = (au.eq.1 .or. au.eq.2)
   mask_vflux    = (av.eq.1 .or. av.eq.2)
   mask_xflux    = (ax.eq.1)
   mask_uupdateU = (au.eq.1)
   mask_vupdateV = (av.eq.1)

!  Note (KK): avoid division by zero layer heights in adv_split_[u|v]
!             (because D[V|U] are not halo-updated)
!             (does not affect flux calculations of H_TAGs)
   mask_uflux(imax+HALO,:) = .false.
   mask_vflux(:,jmax+HALO) = .false.

   adv_gridH%mask_uflux    => mask_uflux
   adv_gridH%mask_vflux    => mask_vflux(_IRANGE_HALO_,_JRANGE_HALO_-1)
   adv_gridH%mask_xflux    => mask_xflux
   adv_gridH%mask_uupdate  => mask_updateH
   adv_gridH%mask_vupdate  => mask_updateH
   adv_gridH%mask_finalise => mask_updateH
   adv_gridH%az            => az

#ifdef _POINTER_REMAP_
   adv_gridU%mask_uflux(_IRANGE_HALO_-1,_JRANGE_HALO_) => mask_updateH(1+_IRANGE_HALO_,_JRANGE_HALO_)
#else
   allocate(mask_ufluxU(_IRANGE_HALO_-1,_JRANGE_HALO_),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (mask_ufluxU)'
   mask_ufluxU = mask_updateH(1+_IRANGE_HALO_,_JRANGE_HALO_)
   adv_gridU%mask_uflux    => mask_ufluxU
#endif
   adv_gridU%mask_vflux    => mask_xflux(_IRANGE_HALO_,_JRANGE_HALO_-1)
#ifdef _POINTER_REMAP_
   adv_gridU%mask_xflux(_IRANGE_HALO_-1,_JRANGE_HALO_) => mask_vflux(1+_IRANGE_HALO_,_JRANGE_HALO_)
#else
   allocate(mask_xfluxU(_IRANGE_HALO_-1,_JRANGE_HALO_),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (mask_xfluxU)'
   mask_xfluxU = mask_vflux(1+_IRANGE_HALO_,_JRANGE_HALO_)
   adv_gridU%mask_xflux    => mask_xfluxU
#endif
   adv_gridU%mask_uupdate  => mask_uupdateU
   adv_gridU%mask_vupdate  => mask_uflux ! now also includes y-advection of u along W/E open bdys
   adv_gridU%mask_finalise => mask_uflux
   adv_gridU%az            => au

   adv_gridV%mask_uflux    => mask_xflux
   adv_gridV%mask_vflux    => mask_updateH(_IRANGE_HALO_,1+_JRANGE_HALO_)
#ifdef _POINTER_REMAP_
   adv_gridV%mask_xflux(_IRANGE_HALO_,_JRANGE_HALO_-1) => mask_uflux(_IRANGE_HALO_,1+_JRANGE_HALO_)
#else
   allocate(mask_xfluxV(_IRANGE_HALO_,_JRANGE_HALO_-1),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (mask_xfluxV)'
   mask_xfluxV = mask_uflux(_IRANGE_HALO_,1+_JRANGE_HALO_)
   adv_gridV%mask_xflux    => mask_xfluxV
#endif
   adv_gridV%mask_uupdate  => mask_vflux ! now also includes x-advection of v along N/S open bdys
   adv_gridV%mask_vupdate  => mask_vupdateV
   adv_gridV%mask_finalise => mask_vflux
   adv_gridV%az            => av

#if defined(SPHERICAL) || defined(CURVILINEAR)
   adv_gridH%dxu   => dxu
   adv_gridH%dyu   => dyu
   adv_gridH%dxv   => dxv(_IRANGE_HALO_,_JRANGE_HALO_-1)
   adv_gridH%dyv   => dyv(_IRANGE_HALO_,_JRANGE_HALO_-1)
   adv_gridH%arcd1 => arcd1

#ifdef _POINTER_REMAP_
   adv_gridU%dxu(_IRANGE_HALO_-1,_JRANGE_HALO_) => dxc(1+_IRANGE_HALO_,_JRANGE_HALO_)
   adv_gridU%dyu(_IRANGE_HALO_-1,_JRANGE_HALO_) => dyc(1+_IRANGE_HALO_,_JRANGE_HALO_)
#else
   allocate(dxuU(_IRANGE_HALO_-1,_JRANGE_HALO_),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (dxuU)'
   allocate(dyuU(_IRANGE_HALO_-1,_JRANGE_HALO_),stat=rc)    ! work array
   if (rc /= 0) stop 'init_advection: Error allocating memory (dyuU)'
   dxuU = dxc(1+_IRANGE_HALO_,_JRANGE_HALO_)
   dyuU = dyc(1+_IRANGE_HALO_,_JRANGE_HALO_)
   adv_gridU%dxu   => dxuU
   adv_gridU%dyu   => dyuU
#endif
   adv_gridU%dxv   => dxx(_IRANGE_HALO_,_JRANGE_HALO_-1)
   adv_gridU%dyv   => dyx(_IRANGE_HALO_,_JRANGE_HALO_-1)
   adv_gridU%arcd1 => arud1

   adv_gridV%dxu   => dxx
   adv_gridV%dyu   => dyx
   adv_gridV%dxv   => dxc(_IRANGE_HALO_,1+_JRANGE_HALO_)
   adv_gridV%dyv   => dyc(_IRANGE_HALO_,1+_JRANGE_HALO_)
   adv_gridV%arcd1 => arvd1
#endif

#ifdef DEBUG
   write(debug,*) 'Leaving init_advection()'
   write(debug,*)
#endif
   return
   end subroutine init_advection
!EOC
!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE:  do_advection - 2D advection schemes \label{sec-do-advection}
!
! !INTERFACE:
   subroutine do_advection(dt,f,U,V,DU,DV,Do,Dn,split,scheme,AH,tag, &
                           Dires,advres)
!
! !DESCRIPTION:
!
! Laterally advects a 2D quantity. The location of the quantity on the
! grid (either T-, U- or V-points) must be specified by the argument
! {\tt tag}. The transports through the interfaces of the corresponding
! Finite-Volumes and their different height information (all relative to
! the given quantity) must be provided as well. Depending on {\tt split}
! and {\tt scheme} several fractional steps (Strang splitting) with
! different options for the calculation of the interfacial fluxes are
! carried out.
!
! The options for {\tt split} are:
!
! \vspace{0.5cm}
!
! \begin{tabular}{ll}
! {\tt split = NOSPLIT}: & no split (one 2D uv step) \\
! {\tt split = FULLSPLIT}: & full step splitting (u + v) \\
! {\tt split = HALFSPLIT}: & half step splitting (u/2 + v + u/2) \\
! \end{tabular}
!
! \vspace{0.5cm}
!
! The options for {\tt scheme} are:
!
! \vspace{0.5cm}
!
! \begin{tabular}{ll}
! {\tt scheme = NOADV}: & advection disabled \\
! {\tt scheme = UPSTREAM}: & first-order upstream (monotone) \\
! {\tt scheme = UPSTREAM\_2DH}: & 2DH upstream with forced monotonicity \\
! {\tt scheme = P2}: & third-order polynomial (non-monotone) \\
! {\tt scheme = SUPERBEE}: & second-order TVD (monotone) \\
! {\tt scheme = MUSCL}: & second-order TVD (monotone) \\
! {\tt scheme = P2\_PDM}: & third-order ULTIMATE-QUICKEST (monotone) \\
! {\tt scheme = J7}: & 2DH Arakawa J7 \\
! {\tt scheme = FCT}: & 2DH FCT with forced monotonicity \\
! {\tt scheme = P2\_2DH}: & 2DH P2 with forced monotonicity \\
! \end{tabular}
!
! \vspace{0.5cm}
!
! With the compiler option {\tt SLICE\_MODEL}, the advection in
! meridional direction is not executed.
!
!
! !USES:
   use halo_zones, only: update_2d_halo,wait_halo,D_TAG,H_TAG,U_TAG,V_TAG
   use getm_timers, only: tic,toc,TIM_ADV,TIM_ADVH
   IMPLICIT NONE
!
! !INPUT PARAMETERS:
   REALTYPE,intent(in)                               :: dt,AH
   REALTYPE,dimension(E2DFIELD),intent(in)           :: U,V,Do,Dn,DU,DV
   integer,intent(in)                                :: split,scheme,tag
!
! !INPUT/OUTPUT PARAMETERS:
   REALTYPE,dimension(E2DFIELD),intent(inout)        :: f
!
! !OUTPUT PARAMETERS:
   REALTYPE,dimension(E2DFIELD),intent(out),optional :: Dires,advres
!
! !LOCAL VARIABLES:
   type(t_adv_grid),pointer :: adv_grid
   integer                  :: j
!
!EOP
!-----------------------------------------------------------------------
!BOC
#ifdef DEBUG
   integer, save :: Ncall = 0
   Ncall = Ncall+1
   write(debug,*) 'do_advection() # ',Ncall
#endif
   call tic(TIM_ADV)

   select case (tag)
      case(H_TAG,D_TAG)
         adv_grid => adv_gridH
      case(U_TAG)
         adv_grid => adv_gridU
      case(V_TAG)
         adv_grid => adv_gridV
      case default
         stop 'do_advection: tag is invalid'
   end select

   Di = Do
   adv = _ZERO_

   if (scheme .ne. NOADV) then

      select case (split)

         case(NOSPLIT)

            select case (scheme)

               case((UPSTREAM),(P2),(SUPERBEE),(MUSCL),(P2_PDM))

                  call adv_split_u(dt,f,Di,adv,U,Do,DU,                       &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                   adv_grid%dxu,adv_grid%dyu,adv_grid%arcd1,  &
#endif
                                   _ONE_,scheme,                              &
#ifdef SLICE_MODEL
                                   SPLIT_UPDATE,                              &
#else
                                   NOSPLIT_NOFINALISE,                        &
#endif
                                   AH,                                        &
                                   adv_grid%mask_uflux,adv_grid%mask_uupdate)
#ifndef SLICE_MODEL
                  call adv_split_v(dt,f,Di,adv,V,Do,DV,                       &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                   adv_grid%dxv,adv_grid%dyv,adv_grid%arcd1,  &
#endif
                                   _ONE_,scheme,NOSPLIT_FINALISE,AH,          &
                                   adv_grid%mask_vflux,adv_grid%mask_vupdate, &
                                   mask_finalise=adv_grid%mask_finalise)
#endif

               case(UPSTREAM_2DH)

                  call adv_upstream_2dh(dt,f,Di,adv,U,V,Do,Dn,DU,DV, &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                        adv_grid%dxv,adv_grid%dyu,   &
                                        adv_grid%dxu,adv_grid%dyv,   &
                                        adv_grid%arcd1,              &
#endif
                                        SPLIT_UPDATE,AH,adv_grid%az)

               case(J7)

                  call adv_arakawa_j7_2dh(dt,f,Di,adv,U,V,Do,Dn,DU,DV, &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                          adv_grid%dxv,adv_grid%dyu,   &
                                          adv_grid%dxu,adv_grid%dyv,   &
                                          adv_grid%arcd1,              &
#endif
                                          SPLIT_UPDATE,AH,adv_grid%az, &
                                          adv_grid%mask_uflux,         &
                                          adv_grid%mask_vflux,         &
                                          adv_grid%mask_xflux)

               case(FCT)

                  call adv_fct_2dh(.true.,dt,f,Di,adv,U,V,Do,Dn,DU,DV, &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                   adv_grid%dxv,adv_grid%dyu,          &
                                   adv_grid%dxu,adv_grid%dyv,          &
                                   adv_grid%arcd1,                     &
#endif
                                   SPLIT_UPDATE,AH,adv_grid%az,        &
                                   adv_grid%mask_uflux,                &
                                   adv_grid%mask_vflux)

               case(P2_2DH)

                  call adv_fct_2dh(.false.,dt,f,Di,adv,U,V,Do,Dn,DU,DV, &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                   adv_grid%dxv,adv_grid%dyu,          &
                                   adv_grid%dxu,adv_grid%dyv,          &
                                   adv_grid%arcd1,                     &
#endif
                                   SPLIT_UPDATE,AH,adv_grid%az,        &
                                   adv_grid%mask_uflux,                &
                                   adv_grid%mask_vflux)

               case default

                  stop 'do_advection: scheme is invalid'

            end select

         case(FULLSPLIT)

            select case (scheme)

               case((UPSTREAM),(P2),(SUPERBEE),(MUSCL),(P2_PDM))

                  call adv_split_u(dt,f,Di,adv,U,Do,DU,                       &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                   adv_grid%dxu,adv_grid%dyu,adv_grid%arcd1,  &
#endif
                                   _ONE_,scheme,SPLIT_UPDATE,AH,              &
                                   adv_grid%mask_uflux,adv_grid%mask_uupdate)
#ifndef SLICE_MODEL
#ifdef GETM_PARALLEL
                  if (scheme.ne.UPSTREAM .and. tag.eq.V_TAG) then
!                    we need to update f(imin:imax,jmax+HALO)
                     call tic(TIM_ADVH)
                     call update_2d_halo(f,f,adv_grid%az,imin,jmin,imax,jmax,H_TAG)
                     call wait_halo(H_TAG)
                     call toc(TIM_ADVH)
                  end if
#endif
                  call adv_split_v(dt,f,Di,adv,V,Do,DV,                       &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                   adv_grid%dxv,adv_grid%dyv,adv_grid%arcd1,  &
#endif
                                   _ONE_,scheme,SPLIT_UPDATE,AH,              &
                                   adv_grid%mask_vflux,adv_grid%mask_vupdate)
#endif

               case((UPSTREAM_2DH),(J7),(FCT),(P2_2DH))

                  stop 'do_advection: scheme not valid for split'

               case default

                  stop 'do_advection: scheme is invalid'

            end select

         case(HALFSPLIT)

            select case (scheme)

               case((UPSTREAM),(P2),(SUPERBEE),(MUSCL),(P2_PDM))

                  call adv_split_u(dt,f,Di,adv,U,Do,DU,                       &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                   adv_grid%dxu,adv_grid%dyu,adv_grid%arcd1,  &
#endif
                                   _HALF_,scheme,SPLIT_UPDATE,AH,             &
                                   adv_grid%mask_uflux,adv_grid%mask_uupdate)
#ifndef SLICE_MODEL
#ifdef GETM_PARALLEL
                  if (scheme.ne.UPSTREAM .and. tag.eq.V_TAG) then
!                    we need to update f(imin:imax,jmax+HALO)
                     call tic(TIM_ADVH)
                     call update_2d_halo(f,f,adv_grid%az,imin,jmin,imax,jmax,H_TAG)
                     call wait_halo(H_TAG)
                     call toc(TIM_ADVH)
                  end if
#endif
                  call adv_split_v(dt,f,Di,adv,V,Do,DV,                       &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                   adv_grid%dxv,adv_grid%dyv,adv_grid%arcd1,  &
#endif
                                   _ONE_,scheme,SPLIT_UPDATE,AH,              &
                                   adv_grid%mask_vflux,adv_grid%mask_vupdate)
#endif
#ifdef GETM_PARALLEL
                  if (scheme .eq. UPSTREAM) then
                     if (tag .eq. U_TAG) then
!                       we need to update f(imax+1,jmin:jmax)
!                       KK-TODO: if external DU was halo-updated this halo-update is not necessary
                        call tic(TIM_ADVH)
                        call update_2d_halo(f,f,adv_grid%az,imin,jmin,imax,jmax,H_TAG)
                        call wait_halo(H_TAG)
                        call toc(TIM_ADVH)
                     end if
                  else
!                    we need to update f(imin-HALO:imin-1,jmin:jmax)
!                    we need to update f(imax+1:imax+HALO,jmin:jmax)
                     call tic(TIM_ADVH)
                     call update_2d_halo(f,f,adv_grid%az,imin,jmin,imax,jmax,H_TAG)
                     call wait_halo(H_TAG)
                     call toc(TIM_ADVH)
                  end if
#endif
                  call adv_split_u(dt,f,Di,adv,U,Do,DU,                       &
#if defined(SPHERICAL) || defined(CURVILINEAR)
                                   adv_grid%dxu,adv_grid%dyu,adv_grid%arcd1,  &
#endif
                                   _HALF_,scheme,SPLIT_UPDATE,AH,             &
                                   adv_grid%mask_uflux,adv_grid%mask_uupdate)

               case((UPSTREAM_2DH),(J7),(FCT),(P2_2DH))

                  stop 'do_advection: scheme not valid for split'

               case default

                  stop 'do_advection: scheme is invalid'

            end select

         case default

            stop 'do_advection: split is invalid'

      end select

#ifdef SLICE_MODEL
      j = jmax/2
      f(:,j+1)   = f(:,j)
      Di(:,j+1)  = Di(:,j)
      adv(:,j+1) = adv(:,j)
      if (tag .eq. V_TAG) then
         f(:,j-1)   = f(:,j)
         Di(:,j-1)  = Di(:,j)
         adv(:,j-1) = adv(:,j)
      end if
#endif

   end if

   if (present(Dires)) Dires = Di
   if (present(advres)) advres = adv

   call toc(TIM_ADV)
#ifdef DEBUG
   write(debug,*) 'Leaving do_advection()'
   write(debug,*)
#endif
   return
   end subroutine do_advection
!EOC
!-----------------------------------------------------------------------
!BOP
!
! !IROUTINE:  print_adv_settings
!
! !INTERFACE:
   subroutine print_adv_settings(split,scheme,AH)
!
! !DESCRIPTION:
!
! Checks and prints out settings for 2D advection.
!
! !USES:
   IMPLICIT NONE

! !INPUT PARAMETERS:
   integer,intent(in)  :: split,scheme
   REALTYPE,intent(in) :: AH
!
! !LOCAL VARIABLES:
!
!EOP
!-------------------------------------------------------------------------
!BOC
#ifdef DEBUG
   integer, save :: Ncall = 0
   Ncall = Ncall+1
   write(debug,*) 'print_adv_settings() # ',Ncall
#endif

   if (scheme .ne. NOADV) then
      select case (split)
         case((NOSPLIT),(FULLSPLIT),(HALFSPLIT))
         case default
            FATAL 'adv_split=',split,' is invalid'
            stop
      end select
   end if

   select case (scheme)
      case((NOADV),(UPSTREAM),(UPSTREAM_2DH),(P2),(SUPERBEE),(MUSCL),(P2_PDM),(J7),(FCT),(P2_2DH))
      case default
         FATAL 'adv_scheme=',scheme,' is invalid'
         stop
   end select

   if (scheme .ne. NOADV) then
      select case (split)
         case((FULLSPLIT),(HALFSPLIT))
            select case (scheme)
               case((UPSTREAM_2DH),(J7),(FCT),(P2_2DH))
                  FATAL 'adv_scheme=',scheme,' not valid for adv_split=',split
                  stop
            end select
      end select
      LEVEL3 trim(adv_splits(split))
   end if

   LEVEL3 ' ',trim(adv_schemes(scheme))

   if (scheme .ne. NOADV) then
      if (AH .gt. _ZERO_) then
         LEVEL3 ' with AH=',AH
      else
         LEVEL3 ' without diffusion'
      end if
   end if

#ifdef DEBUG
   write(debug,*) 'Leaving print_adv_settings()'
   write(debug,*)
#endif
   return
   end subroutine print_adv_settings
!EOC
!-----------------------------------------------------------------------

   end module advection

!-----------------------------------------------------------------------
! Copyright (C) 2001 - Hans Burchard and Karsten Bolding               !
!-----------------------------------------------------------------------