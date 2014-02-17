; docformat = 'rst'
;
;+
;
; Fit a 2D Gaussian to a data cube over a specified wavelength range using 
; MPFIT2DPEAK. The data is first summed over that range.
;
; :Categories:
;    IFSRED
;
; :Returns:
;   Array of peak column and row and half-widths. First column and row are 
;   (1,1).
;
; :Params:
;    cube: in, required, type=structure
;      Contains data cube and associated information, in the form output by 
;      IFSF_READCUBE.
;    lamrange: in, required, type=dblarr(2)
;      Lower and upper limits of wavelength regions to include in fit.
;    
; :Keywords:
;    circ: in, optional, type=byte
;      Enforce fitting of a Gaussian symmetric in x and y.
;    indrange: in, optional, type=byte
;      Give range for wavelength region to fit as indices rather
;      than actual wavelengths. Indices are put in lamrange parameter.
;    quiet: in, optional, type=byte
;      Suppress output of centroids and half-widths to terminal.
;    xranfit: in, optional, type=dblarr(2)
;      Range for fitting centroid, in cube columns. Default is full range.
;    yranfit: in, optional, type=dblarr(2)
;      Range for fitting centroid, in cube rows. Default is full range.
;
; :Author:
;    David S. N. Rupke::
;      Rhodes College
;      Department of Physics
;      2000 N. Parkway
;      Memphis, TN 38104
;      drupke@gmail.com
;
; :History:
;    ChangeHistory::
;      2010jun01, DSNR, created
;      2011may10, DSNR, improved rejection of outliers
;      2014feb06, DSNR, complete rewrite for ease of use/customization;
;                       added detailed documentation
;                       
; :Copyright:
;    Copyright (C) 2014 David S. N. Rupke
;
;    This program is free software: you can redistribute it and/or
;    modify it under the terms of the GNU General Public License as
;    published by the Free Software Foundation, either version 3 of
;    the License or any later version.
;
;    This program is distributed in the hope that it will be useful,
;    but WITHOUT ANY WARRANTY; without even the implied warranty of
;    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;    General Public License for more details.
;
;    You should have received a copy of the GNU General Public License
;    along with this program.  If not, see
;    http://www.gnu.org/licenses/.
;
;-
function ifsr_peak,cube,lamrange,circ=circ,indrange=indrange,quiet=quiet,$
                   xranfit=xranfit,yranfit=yranfit

  if ~ keyword_set(circ) then circular=0 else circular=1

; Indices of fit range in wavelength
  if ~ keyword_set(indrange) then begin
     indrange = intarr(2)
     indrange[0] = value_locate(cube.wave,lamrange[0])
     indrange[1] = value_locate(cube.wave,lamrange[1])
  endif else begin
     indrange = lamrange
  endelse
  
; Fit ranges in X and Y. Else part converts columns and rows that start at 1 
; to zero-offset indices.
  if ~keyword_set(xranfit) then xranfituse=[0,cube.ncols-1] $
  else xranfituse = xranfit - 1
  if ~keyword_set(yranfit) then yranfituse=[0,cube.nrows-1] $
  else yranfituse = yranfit - 1

  datsub = cube.dat[xranfituse[0]:xranfituse[1],$
                    yranfituse[0]:yranfituse[1],$
                    indrange[0]:indrange[1]]
  varsub = cube.var[xranfituse[0]:xranfituse[1],$
                    yranfituse[0]:yranfituse[1],$
                    indrange[0]:indrange[1]]
  dqsub = cube.dq[xranfituse[0]:xranfituse[1],$
                  yranfituse[0]:yranfituse[1],$
                  indrange[0]:indrange[1]]

; Zero out DQed data
  ibad = where(dqsub eq 1)
  datsub[ibad] = 0
  varsub[ibad] = 0

; Sum over wavelength space
  datsum = total(datsub,3,/double)
  varsum = total(varsub,3,/double)

; Normalize by number of wavelength pixels summed
  fluxct = (indrange[1]-indrange[0]+1) - total(dqsub,3,/double)
  datsum /= fluxct
  varsum /= fluxct

; Flag spaxels with no data
  inoflux = where(fluxct eq 0,ctnoflux)
  if ctnoflux gt 0 then begin
    datsum[inoflux]=0d
    varsum[inoflux]=1d99
  endif
  
  yfit = mpfit2dpeak(datsum,param,weights=1d/varsum,circular=circular)
; Output parameters are central flux, half widths, and centroids. +1 converts 
; from 0-offset indices to cols and rows that start at 1.
  fc=param[1]
  xhw=param[2]
  yhw=param[3]
  xc=param[4]+xranfituse[0]+1
  yc=param[5]+yranfituse[0]+1

  if not keyword_set(quiet) then begin
     print,'Peak flux at [',xc,',',yc,'] is ',fc,$
        format='(A0,D0.1,A0,D0.1,A0,E0.2)'
     print,'X/Y-widths: ',xhw,' / ',yhw,format='(A0,D0.2,A0,D0.2)'
  endif

  return,[xc,yc,xhw,yhw]

end