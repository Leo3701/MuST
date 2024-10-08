subroutine startProcess(ss_mode)
   use KindParamModule, only : IntKind, RealKind, CmplxKind
!
   use MathParamModule, only : TEN2m6, ONE
!
   use TimerModule, only : initTimer
!
   use ErrorHandlerModule, only : ErrorHandler, WarningHandler
!
   use MPPModule, only : initMPP, MyPE
!
   use GroupCommModule, only : initGroupComm, getGroupID
!
   use ParallelIOModule, only : initParallelIO
!
   use DataServiceCenterModule, only : initDataServiceCenter
!
   use CheckPointModule, only : initCheckPoint
!
   use InputModule, only : initInput
!
   use OutputModule, only : initOutput, getStandardOutputLevel
!
   use ScfDataModule, only : initScfData, printScfData, getPotentialTypeParam
   use ScfDataModule, only : isLSMS
   use ScfDataModule, only : NumKMeshs, kGenScheme, Kdiv, Symmetrize
   use ScfDataModule, only : isReadEmesh, getEmeshFileName
   use ScfDataModule, only : isReadKmesh, getKmeshFileName
   use ScfDataModule, only : eGridType, NumEs, ContourType, NumSS_IntEs, Temperature
!
   use PotentialTypeModule, only : initPotentialType, printPotentialType, &
                                   isFullPotential
!
   use SystemModule, only : initSystem, printSystem, getNumAtoms, getLmaxKKR
   use SystemModule, only : getBravaisLattice, getAtomPosition, getAtomicNumber
!
   use SystemVolumeModule, only : initSystemVolume, setSystemVolumeMT,  &
                                  updateSystemVolume
!
   use ProcMappingModule, only : initProcMapping, createParallelization
!
   use Atom2ProcModule, only : initAtom2Proc, getLocalNumAtoms
!
   use AtomModule, only : initAtom, printAtom, getMuffinTinRadius, setMuffinTinRadius
   use AtomModule, only : getAtomCoreRad, setAtomCoreRad
!
   use ContourModule, only : initContour, getNumEs
!
   use BZoneModule, only : initBZone, getNumKs
!
   use PolyhedraModule, only : getInscrSphRadius
!
   implicit none
!
   logical :: isRmtUpdated
!
   character (len=8)  :: exec_date
   character (len=10) :: exec_time
!
   integer (kind=IntKind), intent(in), optional :: ss_mode
   integer (kind=IntKind) :: def_id, info_id
   integer (kind=IntKind) :: NumAtoms, ne, nk, i, LocalNumAtoms
   integer (kind=IntKind), pointer :: AtomicNumber(:)
!
   real (kind=RealKind) :: bravais(3,3), rmt, rinsc
   real (kind=RealKind), pointer :: AtomPosition(:,:)
!
!  -------------------------------------------------------------------
   call initTimer()
!  -------------------------------------------------------------------
   call initMPP()
   if (MyPE == 0) then
      call date_and_time(exec_date,exec_time)
      write(6,'(/,12a)')'Setup starts at ',                           &
           exec_time(1:2),':',exec_time(3:4),':',exec_time(5:6),', ', &
           exec_date(5:6),'-',exec_date(7:8),'-',exec_date(1:4)
      write(6,'(80(''-''))')
   endif
   call initGroupComm()
   call initCheckPoint()
   call initDataServiceCenter()
   call initInput()
   call readInputs(def_id,info_id)
   call initScfData(def_id)
   call initPotentialType(getPotentialTypeParam())
   call initSystem(def_id)
!  -------------------------------------------------------------------
!  
   NumAtoms = getNumAtoms()
   if (NumAtoms < 1) then
      call ErrorHandler('startProcess','invalid NumAtoms',NumAtoms)
   endif
!
   if (isReadEmesh()) then
!     ----------------------------------------------------------------
      call initContour(getEmeshFileName(), 'none', -1)
!     ----------------------------------------------------------------
   else
!     ----------------------------------------------------------------
      call initContour( ContourType, eGridType, NumEs, Temperature, 'none', -1)
!     ----------------------------------------------------------------
   endif
   ne = getNumEs()
   if ( present(ss_mode) ) then
      if (ss_mode == 1) then
         ne = NumSS_IntEs
      endif
   endif
      
!
   bravais(1:3,1:3)=getBravaisLattice()
   NumAtoms = getNumAtoms()
   AtomPosition => getAtomPosition()
   AtomicNumber => getAtomicNumber()
   if (.not.isLSMS()) then
      if (isReadKmesh()) then
!        -------------------------------------------------------------
         call initBZone(getKmeshFileName(),'none',-1)
!        -------------------------------------------------------------
      else if (NumKMeshs > 0) then
!        -------------------------------------------------------------
         call initBZone(NumKMeshs,kGenScheme,Kdiv,Symmetrize,bravais, &
                        NumAtoms,AtomPosition,AtomicNumber,'none',-1)
!        -------------------------------------------------------------
      else
!        -------------------------------------------------------------
         call WarningHandler('main','No K mesh is initialized')
!        -------------------------------------------------------------
      endif
      nk = getNumKs()
   else
      nk = (getLmaxKKR()+1)**2
   endif
!
!  ===================================================================
!  Initialize the processes mapping module that determines how the
!  parallization will be performed
!  -------------------------------------------------------------------
   call initProcMapping(NumAtoms, ne, nk, isFullPotential(), 'none', 0, NumAtoms)
!  -------------------------------------------------------------------
   call createParallelization()
!  -------------------------------------------------------------------
   call initParallelIO(getGroupID('Unit Cell'),1) ! only the 1st cluster
                                                  ! in the group performs
                                                  ! writing potential data
!  -------------------------------------------------------------------
   call initAtom2Proc(NumAtoms, NumAtoms)
!  -------------------------------------------------------------------
   call initSystemVolume()
!  -------------------------------------------------------------------
!
!  ===================================================================
!  set up print level
!  -------------------------------------------------------------------
   call initOutput(def_id)
!  -------------------------------------------------------------------
!
!  ===================================================================
!  call initAtom and setAtomData to setup Atom Module.................
!  -------------------------------------------------------------------
   call initAtom(info_id,'none',getStandardOutputLevel())
!  -------------------------------------------------------------------
!
   LocalNumAtoms=getLocalNumAtoms()
   isRmtUpdated = .false.
   do i = 1,LocalNumAtoms
      rmt   = getMuffinTinRadius(i)
      rinsc = getInscrSphRadius(i)
      if (rmt < ONE) then
         if (abs(rmt) < TEN2m6) then
!           ==========================================================
!           The muffin-tin radius is set to be the inscribed radius.
!           ==========================================================
            rmt = rinsc
         else
!           ==========================================================
!           In this case, rmt is treated as a scaling factor for rinsc
!           The muffin-tin radius is set to be the inscribed radius
!           multiplied by the scaling factor
!           ==========================================================
            rmt = rmt*rinsc
         endif
!        -------------------------------------------------------------
         call setMuffinTinRadius(i,rmt)
!        -------------------------------------------------------------
         if (.not.isFullPotential()) then
!           ==========================================================
!           For Muffin-tin, ASA, or Muffin-tin-ASA calculations, since
!           potential outside rmt is 0, core radius is set to rmt
!           ----------------------------------------------------------
            call setAtomCoreRad(i,rmt)
!           ----------------------------------------------------------
         endif
      endif
!
      if ( abs(rinsc-rmt) > TEN2m6) then
!        =============================================================
!        The muffin-tin radius is set to be other than the inscribed radius.
!        -------------------------------------------------------------
         call setSystemVolumeMT(i,rmt)
!        -------------------------------------------------------------
         isRmtUpdated = .true.
      endif
   enddo
   if ( isRmtUpdated ) then
!     ----------------------------------------------------------------
      call updateSystemVolume()
!     ----------------------------------------------------------------
   endif
!
   if (getStandardOutputLevel() >= 0) then
!     ----------------------------------------------------------------
      call printPotentialType()
      call printScfData()
      call printSystem()
      call printAtom()
!     ----------------------------------------------------------------
   endif
!
end subroutine startProcess
