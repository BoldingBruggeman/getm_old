!$Id: grid_ncdf.F90,v 1.1 2005-04-25 09:32:34 kbk Exp $
#include "cppdefs.h"
!-----------------------------------------------------------------------
!BOP
!
! !MODULE: Encapsulate grid related quantities
!
! !INTERFACE:
   module grid_ncdf
!
! !DESCRIPTION:
! This module is a container for grid related variables and
! parameters which are used jointly by different parts of the
! netCDF storage system.
!
! !USES:
   IMPLICIT NONE
!
! !PUBLIC DATA MEMBERS:
   integer                             :: xlen,ylen,zlen

! !DEFINED PARAMETERS
   REALTYPE, parameter                 :: h_missing      =-10.0
   REALTYPE, parameter                 :: xy_missing     =-9999.0
   REALTYPE, parameter                 :: latlon_missing =-9999.0
   REALTYPE, parameter                 :: conv_missing   =-9999.0
!
! !REVISION HISTORY:
!  Original author(s): Lars Umlauf
!
!  $Log: grid_ncdf.F90,v $
!  Revision 1.1  2005-04-25 09:32:34  kbk
!  added NetCDF IO rewrite + de-stag of velocities - Umlauf
!
!
!EOP
!-----------------------------------------------------------------------

   end module grid_ncdf

!-----------------------------------------------------------------------
! Copyright (C) 2005 - Lars Umlauf, Hans Burchard and Karsten Bolding
!-----------------------------------------------------------------------