!$Id: ip_z_interpol.F90,v 1.1 2004-04-06 12:42:50 kbk Exp $
#include "cppdefs.h"
!-----------------------------------------------------------------------
!BOP
!
! !ROUTINE: ip_z_interpol()
!
! !INTERFACE:
   subroutine ip_z_interpol()
!
! !DESCRIPTION:
!
! !USES:
   use internal_pressure
   IMPLICIT NONE
!
! !REVISION HISTORY:
!  Original author(s): Hans Burchard & Karsten Bolding
!
!  $Log: ip_z_interpol.F90,v $
!  Revision 1.1  2004-04-06 12:42:50  kbk
!  internal pressure calculations now uses wrapper
!
!
! !LOCAL VARIABLES:
   integer                   :: i,j,k
   REALTYPE                  :: dxm1,dym1
   REALTYPE                  :: grdl,grdu,rhol,rhou,prgr,dxz,dyz
   integer                   :: kplus,kminus
   REALTYPE                  :: zx(kmax)
   REALTYPE                  :: rhoplus,rhominus
!EOP
!-----------------------------------------------------------------------
!BOC
#if ! ( defined(SPHERICAL) || defined(CURVILINEAR) )
   dxm1 = _ONE_/DXU
   dym1 = _ONE_/DYV
#endif

!  First, the heights of the pressure points are calculated.
   do j=jjmin,jjmax+1
      do i=iimin,iimax+1
         if (az(i,j) .ge. 1) then
            zz(i,j,1)=-H(i,j)+0.5*hn(i,j,1)
            do k=2,kmax
               zz(i,j,k)=zz(i,j,k-1)+0.5*(hn(i,j,k-1)+hn(i,j,k))
            end do
         end if
      end do
   end do

!  Calculation of layer integrated internal pressure gradient as it
!  appears on the right hand side of the u-velocity equation.
   do j=jjmin,jjmax
      do i=iimin,iimax
         if (au(i,j) .ge. 1) then
#if defined(SPHERICAL) || defined(CURVILINEAR)
            dxm1=_ONE_/DXU
#endif
            zx(1)=-HU(i,j)+0.5*hun(i,j,1) ! zx defined on u-points
            do k=2,kmax
               zx(k)=zx(k-1)+0.5*(hun(i,j,k-1)+hun(i,j,k))
            end do
            grdl=0.5*hun(i,j,kmax)*(rho(i+1,j,kmax)-rho(i,j,kmax))*dxm1
            rhol=0.5*(rho(i+1,j,kmax)+rho(i,j,kmax))
            prgr=grdl
            idpdx(i,j,kmax)=hun(i,j,kmax)*prgr
            do k=kmax-1,1,-1
               grdu=grdl
               do kplus=kmax,1,-1  ! Find neighboring index to east
                  if (zz(i+1,j,kplus) .le. zx(k)) EXIT
               end do
               do kminus=kmax,1,-1 ! Find neighboring index to west
                  if (zz(i,j,kminus) .le. zx(k)) EXIT
               end do
               if (kplus .eq. kmax) rhoplus=rho(i+1,j,kplus)
               if (kplus .lt. kmax .and. kplus .gt. 1) then ! interpolate
                  rhoplus=((zx(k)-zz(i+1,j,kplus))*rho(i+1,j,kplus+1)+ &
                          (zz(i+1,j,kplus+1)-zx(k))*rho(i+1,j,kplus))/ &
                          (0.5*(hn(i+1,j,kplus+1)+hn(i+1,j,kplus)))
               end if
               if (kminus .eq. kmax) rhominus=rho(i,j,kminus)
               if ((kminus .lt. kmax) .and. (kminus .gt. 1)) then ! interpolate
                  rhominus=((zx(k)-zz(i,j,kminus))*rho(i,j,kminus+1)+ &
                          (zz(i,j,kminus+1)-zx(k))*rho(i,j,kminus))/  &
               (0.5*(hn(i,j,kminus+1)+hn(i,j,kminus)))
               end if
               if (zx(k) .gt. max(-H(i+1,j),-H(i,j))) then
                  grdl=0.5*hun(i,j,k)*(rhoplus-rhominus)*dxm1
               else
                  grdl= _ZERO_
               end if
               prgr=prgr+grdu+grdl
               idpdx(i,j,k)=hun(i,j,k)*prgr
            end do
         end if
      end do
   end do

! Calculation of layer integrated internal pressure gradient as it
! appears on the right hand side of the v-velocity equation.
   do j=jjmin,jjmax
      do i=iimin,iimax
         if (av(i,j) .ge. 1) then
#if defined(SPHERICAL) || defined(CURVILINEAR)
         dym1 = _ONE_/DYV
#endif
            zx(1)=-HV(i,j)+0.5*hvn(i,j,1) ! zx defined on v-points
            do k=2,kmax
               zx(k)=zx(k-1)+0.5*(hvn(i,j,k-1)+hvn(i,j,k))
            end do
            grdl=0.5*hvn(i,j,kmax)*(rho(i,j+1,kmax)-rho(i,j,kmax))*dym1
            rhol=0.5*(rho(i,j+1,kmax)+rho(i,j,kmax))
            prgr=grdl
            idpdy(i,j,kmax)=hvn(i,j,kmax)*prgr
            do k=kmax-1,1,-1
               grdu=grdl
               do kplus=kmax,1,-1  ! Find neighboring index to north
                  if (zz(i,j+1,kplus) .le. zx(k)) EXIT
               end do
               do kminus=kmax,1,-1 ! Find neighboring index to south
                  if (zz(i,j,kminus) .le. zx(k)) EXIT
               end do
               if (kplus .eq. kmax) rhoplus=rho(i,j+1,kplus)
               if ((kplus .lt. kmax) .and. (kplus .gt. 1)) then
                  rhoplus=((zx(k)-zz(i,j+1,kplus))*rho(i,j+1,kplus+1)+ &
                          (zz(i,j+1,kplus+1)-zx(k))*rho(i,j+1,kplus))/ &
                          (0.5*(hn(i,j+1,kplus+1)+hn(i,j+1,kplus)))
               end if
               if (kminus .eq. kmax) rhominus=rho(i,j,kminus)
               if ((kminus .lt. kmax) .and. (kminus .gt. 1)) then
                  rhominus=((zx(k)-zz(i,j,kminus))*rho(i,j,kminus+1)+  &
                           (zz(i,j,kminus+1)-zx(k))*rho(i,j,kminus))/  &
                           (0.5*(hn(i,j,kminus+1)+hn(i,j,kminus)))
               end if
               if (zx(k).gt.max(-H(i,j+1),-H(i,j))) then
                  grdl=0.5*hvn(i,j,k)*(rhoplus-rhominus)*dym1
               else
                  grdl= _ZERO_
               end if
               prgr=prgr+grdu+grdl
               idpdy(i,j,k)=hvn(i,j,k)*prgr
            end do
         end if
      end do
   end do

   return
   end subroutine ip_z_interpol
!EOC

!-----------------------------------------------------------------------
! Copyright (C) 2004 - Hans Burchard and Karsten Bolding               !
!-----------------------------------------------------------------------