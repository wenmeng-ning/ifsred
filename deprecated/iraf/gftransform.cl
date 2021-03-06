# Copyright(c) 2002-2012 Association of Universities for Research in Astronomy, Inc.

procedure gftransform(inimages)

# Wavelength calibrate GMOS IFU data
#
# Version  Sept 20, 2002 BM v1.4 release
#          Aug 25, 2003  KL IRAF2.12 - new parameter, addonly, in hedit
#          Feb 29, 2004  BM Fixed bug in definition of l_wavtraname
#          Mar 19, 2004  BM Add APID column updating
#          Mar 24, 2004  BM Exit gracefully if wav cal databases not found

string inimages     {prompt="Input GMOS IFU spectra"}
string outimages    {"",prompt="Output spectra"}
string outpref      {"t",prompt="Prefix for output spectra"}
string wavtraname   {"",prompt="Names of wavelength calibrations"}
string database     {"database",prompt="Directory for calibration files"}
bool   fl_vardq     {no,prompt="Transform variance and data quality planes"}
bool   fl_flux      {yes,prompt="Conserve flux per pixel in the transform"}
string  sci_ext     {"SCI",prompt="Name of science extension"}
string  var_ext     {"VAR",prompt="Name of variance extension"}
string  dq_ext      {"DQ",prompt="Name of data quality extension"}
string  logfile     {"",prompt="Logfile"}
bool    verbose     {yes,prompt="Verbose"}
int     status      {0,prompt="Exit status (0=good)"}
struct* scanfile1   {"",prompt="Internal use"}
struct* scanfile2   {"",prompt="Internal use"}

begin

    string l_inimages, l_outimages, l_prefix, l_sdistname
    string l_wavtraname
    string l_grating, l_filter, l_gratingdb, l_filterdb
    string l_database, l_interptype, l_sci_ext, l_var_ext, l_dq_ext
    string l_logfile, l_fitcfunc
    string scilistin,scilistout,dum,displog, outdq
    real   w1,w2,dw,w1max,w2min,dwav, dqthresh
    bool   l_fl_vardq, l_fl_wavtran, l_fl_stran
    bool   l_fl_interac, l_xlog, l_ylog, l_flux, l_verbose
    int    l_spatbin, l_specbin, l_fitcxord, l_fitcyord, l_status
    int    nw,ndum

    #Other variables used within this task
    file   temp1,temp2,temp3,wavlist,sdistlist,tmpsci,tmpvar,tmpdq,mdf
    string inlist,outlist,img,outimg,snum,infile[100]
    string wcalfile,scalfile,wcal,scal,fitname,scopyout,vcopyout,dcopyout
    string obsmode,dbprefix, suf
    string ffile,fname,gname
    string varlistin,varlistout,dqlistin,dqlistout, dqexpr
    int    nbad,nin,nout,nwavfil,ndistfil,nsciext,nextens,i
    int    nsciin,nsciout,sel,nextnd,mdfrow,apid
    bool   useprefix,go
    struct sdate

    # Initialize exit status
    status=0

    # cache some parameter files
    cache("imgets","gmos","gimverify","tinfo","tabpar","gemdate")

    # Set the local variables
    l_inimages=inimages ; l_outimages=outimages ; l_prefix=outpref
    l_wavtraname=wavtraname ; l_database=database
    l_fl_vardq=fl_vardq ; l_flux=fl_flux
    l_sci_ext=sci_ext ; l_var_ext=var_ext ; l_dq_ext=dq_ext
    l_logfile=logfile ; l_verbose=verbose
    dbprefix="id"
    l_fl_stran = no
    l_fl_wavtran = yes
    dqthresh = 0.1

    # temporary files
    wavlist=mktemp("tmpwavlist")
    temp3=mktemp("tmpfilelist")
    displog=mktemp("tmpdisplog")

    # Test the logfile:
    gemlogname(logpar=l_logfile,package="gmos")
    if (gemlogname.status != 0)
         goto error
    l_logfile=gemlogname.logname

    # Start logging
    printlog("-------------------------------------------------------------------------------", \
        l_logfile,l_verbose)
    date | scan(sdate)
    printlog("GFTRANSFORM -- "//sdate,l_logfile,l_verbose)
    printlog(" ",l_logfile,verbose=l_verbose)

    #The usual kind of checks to make sure everything we need is specified.
    nbad=0

    if (l_inimages=="" || l_inimages==" ") {
        printlog("ERROR - GFTRANSFORM: Input spectra is an empty string",
             l_logfile,verbose+)
        nbad=nbad+1
    }

    if (substr(l_inimages,1,1)=="@") {
        inlist=substr(l_inimages,2,strlen(l_inimages))
        if (!access(inlist)) {
             printlog("ERROR - GFTRANSFORM: Input list "//inlist//" not found",
                 l_logfile,verbose+)
             nbad=nbad+1
        }
    }

    if ((l_outimages=="" || l_outimages==" ") && \
        (l_prefix=="" || l_prefix==" ")) {
        printlog("ERROR - GFTRANSFORM: Neither the output spectra \
            nor prefix is specified.",
            l_logfile,verbose+)
        nbad=nbad+1
    } else if ((l_outimages!="" && l_outimages!=" ")) {
        useprefix=no
    } else
        useprefix=yes

    if (substr(l_outimages,1,1)=="@") {
        outlist=substr(l_outimages,2,strlen(l_outimages))
        if (!access(outlist)) {
            printlog("ERROR - GFTRANSFORM: Output list "//outlist//\
                " not found",
                l_logfile,verbose+)
            nbad=nbad+1
        }
    }

    temp1=mktemp("tmpin")
    temp2=mktemp("tmpout")
    files(l_inimages,sort-, > temp1)
    count(temp1) | scan(nin)
    if (!useprefix) {
         files(l_outimages,sort-, > temp2)
         count(temp2) | scan(nout)
         if (nin != nout) {
            printlog("ERROR - GFTRANSFORM: Different number of input \
                and output spectra", l_logfile,verbose+)
            nbad=nbad+1
         }
    } else {
        files(l_prefix//"//@"//temp1,sort-, > temp2)
    }

    #Wavelength calibrations
    if (substr(l_wavtraname,1,1)=="@") {
         woutlist=substr(l_wavtraname,2,strlen(l_wavtraname))
         if (!access(woutlist)) {
             printlog("ERROR - GFTRANSFORM: Output list "//woutlist//\
                 " not found",
                 l_logfile,verbose+)
             nbad=nbad+1
         }
    }
    if (nbad == 0) {
         files(l_wavtraname,sort-, > wavlist)
         count(wavlist) | scan(nwavfil)
         if (nwavfil != 1 && nwavfil != nin) {
             printlog("ERROR - GFTRANSFORM: Number of wavelength calibration \
                 images must be 1, or ", l_logfile,verbose+)
             printlog("                     equal to the number of input \
                 images.",
                 l_logfile,verbose+)
             nbad=nbad+1
         }
         if (nwavfil == 1 && nbad==0) {
            delete(wavlist,verify-)
             for(i=1;i<=nin;i+=1) {
                  print(l_wavtraname, >> wavlist)
             }
         }
    }

    if (l_sci_ext=="" || l_sci_ext==" ") {
         printlog("ERROR - GFTRANSFORM: extension name sci_ext is missing",
             l_logfile,verbose+)
         nbad=nbad+1
    }

    #If var propogation is requested, make sure the names are given
    if (l_fl_vardq) {
        if (l_dq_ext=="" || l_dq_ext ==" ") {
            printlog("ERROR - GFTRANSFORM: extension name dq_ext is missing",
                 l_logfile,verbose+)
            nbad=nbad+1
        } else if (l_var_ext=="" || l_var_ext ==" ") {
            printlog("ERROR - GFTRANSFORM: extension name var_ext is missing",
                 l_logfile,verbose+)
            nbad=nbad+1
        }
    }

    # check no commas in sci_ext, var_ext and dq_ext
    if (stridx(",",l_sci_ext)>0 || stridx(",",l_var_ext)>0 || \
        stridx(",",l_dq_ext)>0 ) {
        printlog("ERROR - GFTRANSFORM: sci_ext, var_ext or dq_ext contains \
             commas, give root name only",
             l_logfile,verbose+)
        nbad=nbad+1
    }

    i=0
    scanfile1=temp1
    while (fscan(scanfile1,img) !=EOF) {
         gimverify(img)
         if (gimverify.status>0)
             nbad=nbad+1
         else {
            i=i+1
            # name w/o suffix
            infile[i]=gimverify.outname
         }

    }  #end of while loop over images.
    scanfile1=""

    #If anything was wrong then exit.

    if (nbad > 0) {
         printlog("ERROR - GFTRANSFORM: "//nbad//" errors found with input \
             parameters. Exiting.", l_logfile,verbose+)
         goto error
    }

    #If we are here then everything should be OK.
    #Write all the relevant info to the logfile:
    printlog("inimages   = "//l_inimages,l_logfile,l_verbose)
    printlog("outimages  = "//l_outimages,l_logfile,l_verbose)
    printlog("outpref    = "//l_prefix,l_logfile,l_verbose)
    printlog("wavtraname = "//l_wavtraname,l_logfile,l_verbose)
    printlog("database   = "//l_database,l_logfile,l_verbose)
    printlog("fl_vardq   = "//l_fl_vardq,l_logfile,l_verbose)
    printlog("fl_flux    = "//l_flux,l_logfile,l_verbose)
    printlog(" ",l_logfile,l_verbose)

    #Join lists together. The logic here is a tad confusing but it generates a
    #structured filelist which includes the input file, outputfile name (MEF),
    #and the transformation database(s) to use for each image in the
    #input list - all on one line per image to be transformed.
    #

    # Make list file for main loop
    joinlines (temp1//","//temp2//","//wavlist, output=temp3, delim=" ", \
        missing="Missing", maxchar=161, shortest=yes, verbose=no)
    scanfile1=temp3
    while (fscan(scanfile1,img,outimg,wcal) != EOF) {
        # create tmp FITS file names used only within this loop.
         scopyout=mktemp("tmpscopyout")

        if (l_fl_vardq) {
            vcopyout=mktemp("tmpscopyout")
            dcopyout=mktemp("tmpscopyout")
         }

         # check .fits
         suf=substr(img,strlen(img)-4,strlen(img))
         if (suf!=".fits")
           img=img//".fits"

         suf=substr(outimg,strlen(outimg)-4,strlen(outimg))
         if (suf!=".fits")
           outimg=outimg//".fits"

         # copy MDF
         mdf=mktemp("tmpmdf")
         tcopy(img//"[MDF]",mdf//".fits",verbose-)
         wmef(mdf//".fits",outimg,extnames="MDF",verb-,phu=img, >& "dev$null")
         imdelete (mdf, verify-, >& "dev$null")

         # get obsmode
         imgets(img//"[0]","OBSMODE")
         obsmode=imgets.value
         if (obsmode != "IFU") {
             printlog("ERROR - GFTRANSFORM: image "//img//" was not taken \
                 with the IFU", l_logfile,verbose+)
             goto error
         }

         scilistin=""
         scilistout=""

         # get number of rows in MDF
         imgets(img//"[0]","NSCIEXT")
         nsciin=int(imgets.value)

         # Loop over extensions
         for (i=1; i<=nsciin; i+=1) {
            if (i < 10)
                 snum="00"//i
            else if (i < 100)
                 snum="0"//i
            else
                 snum=str(i)
            wcalfile=wcal//"_"//snum
            tmpsci=mktemp("tmpsci")
            tmpvar=mktemp("tmpvar")
            tmpdq=mktemp("tmpdq")
            go=access(l_database//"/"//dbprefix//wcalfile)
            if (go && imaccess(img//"["//l_sci_ext//","//i//"]")) {
                printlog ("Transforming "//img//"["//l_sci_ext//","//i//"]",
                      l_logfile,l_verbose)

                # science plane
                gemhedit (img//"["//l_sci_ext//","//i//"]", "REFSPEC1", \
                   wcalfile, "", delete-)

                # List dispersion coordinates
                dispcor(img//"["//l_sci_ext//","//i//"]","",linear+,
                    database=l_database,table="",w1=INDEF,w2=INDEF,dw=INDEF,
                    nw=INDEF,log-,flux=l_flux,samedisp+,global+,ignoreaps-,
                    listonly+,verbose+,logfile=l_logfile,confirm-) | \
                    translit("STDIN","=,"," ",delete-, > displog)

                scanfile2=displog
                ndum=fscan(scanfile2,dum)
                ndum=fscan(scanfile2,dum,dum,dum,w1,dum,w2,dum,dw,dum,nw)
                scanfile2=""
                delete(displog,verify-)
                print(w1," ",w2," ",dw)
                if (i==1) {
                    w1max=w1
                    w2min=w2
                    dwav=dw
                    scilistin=img//"["//l_sci_ext//","//i//"]"
                    scilistout=tmpsci
                } else {
                    if (w1>w1max)
                       w1max=w1
                    if (w2<w2min)
                        w2min=w2
                    dwav=(dwav+dw)/2.
                    scilistin=scilistin//","//img//"["//l_sci_ext//","//i//"]"
                    scilistout=scilistout//","//tmpsci
                }

                if (l_fl_vardq) {
                    if (imaccess(img//"["//l_var_ext//","//i//"]") && \
                        imaccess(img//"["//l_dq_ext//","//i//"]")) {
                        # variance plane
                        gemhedit(img//"["//l_var_ext//","//i//"]", "REFSPEC1",
                            wcalfile, "", delete-)
                        # dq plane
                        gemhedit(img//"["//l_dq_ext//","//i//"]", "REFSPEC1",
                            wcalfile, "", delete-)
                        if (i==1) {
                            varlistin = img//"["//l_var_ext//","//i//"]"
                            varlistout = tmpvar
                            dqlistin = img//"["//l_dq_ext//","//i//"]"
                            dqlistout = tmpdq
                        } else {
                            varlistin = varlistin//","//img//\
                                "["//l_var_ext//","//i//"]"
                            varlistout = varlistout//","//tmpvar
                            dqlistin = dqlistin//","//img//\
                                "["//l_dq_ext//","//i//"]"
                            dqlistout = dqlistout//","//tmpdq
                        }
                    } else {
                        printlog ("WARNING - GFTRANSFORM: Cannot access "//\
                            img//"["//l_var_ext//","//i//"] or "//\
                            img//"["//l_dq_ext//","//i//"]", \
                            l_logfile, verbose+)
                        printlog ("                       Setting fl_vardq to \
                            no", l_logfile, verbose+)
                    }
                }
            } else {
                printlog("ERROR - GFTRANSFORM: Wavelength calibration file \
                    or image extension "//i//" not found",\
                    l_logfile, verbose+)
                goto error
            }
        }
        # run dispcor
        dispcor(scilistin,scilistout,linear+,database=l_database,table="",
            w1=w1max,w2=w2min,dw=dwav,nw=INDEF,log-,flux=l_flux,samedisp+,
            global+,ignoreaps-,listonly-,verbose=l_verbose,logfile=l_logfile,
            confirm-)

        if (l_fl_vardq) {
            dispcor(varlistin,varlistout,linear+,database=l_database,table="",
                w1=w1max,w2=w2min,dw=dwav,nw=INDEF,log-,flux=l_flux,samedisp+,
                global+,ignoreaps-,listonly-,verbose=l_verbose,\
                logfile=l_logfile, confirm-)

            dispcor(dqlistin,dqlistout,linear+,database=l_database,table="",
                w1=w1max,w2=w2min,dw=dwav,nw=INDEF,log-,flux=l_flux,samedisp+,
                global+,ignoreaps-,listonly-,verbose=l_verbose,\
                logfile=l_logfile, confirm-)
        }

        ## Put transformed slit in output file
        imgets(outimg//"[0]","NEXTEND")
        nextnd=int(imgets.value)
        scopy(scilistout,scopyout//".fits",renum+,merge+,clobber+,verb-,rebin-)
        fxinsert(scopyout//".fits",outimg//"["//nextnd//"]","0",verbose-,
            >& "dev$null")
        nextnd=nextnd+1
        gemhedit (outimg//"[0]", "NEXTEND", nextnd, "", delete-)
        gemhedit (outimg//"["//nextnd//"]", "EXTNAME", l_sci_ext, "", delete-)
        gemhedit (outimg//"["//nextnd//"]", "EXTVER", 1, "", delete-)
        gemhedit (outimg//"["//nextnd//"]", "WAVTRAN", wcalfile, "", delete-)

        imdelete(scilistout//","//scopyout,verify-, >& "dev$null")

        # Variance and DQ
        if (l_fl_vardq) {
            scopy(varlistout, vcopyout, renum+, merge+, clobber+, \
                verb-, rebin-)
            scopy(dqlistout, dcopyout, renum+, merge+, clobber+, \
                verb-, rebin-)

            dqexpr = "a > b ? 1 : 0"
            outdq = mktemp ("outdq")
            imexpr (dqexpr, outdq, dcopyout, dqthresh, dims="auto", \
                intype="auto", outtype="ushort", refim="auto", bwidth=0, \
                btype="nearest", bpixval=0., rangecheck=yes, verbose=no)

            fxinsert(vcopyout//","//outdq,
                outimg//"["//nextnd//"]","0",verbose-, >& "dev$null")

            imdelete (varlistout//","//dqlistout//","//\
                vcopyout//","//dcopyout//","//outdq, verify-, \
                >& "dev$null")

            gemhedit (outimg//"[0]","NEXTEND", (nextnd+2), "", delete-)

            # Variance header
            gemhedit(outimg//"["//(nextnd+1)//"]", "EXTNAME", l_var_ext, \
                "", delete-)
            gemhedit(outimg//"["//(nextnd+1)//"]", "EXTVER", 1, "", delete-)

            if (l_fl_stran) {
                gemhedit(outimg//"["//(nextnd+1)//"]", "SDISTNAM", \
                    scalfile, "", delete-)
            }

            if (l_fl_wavtran) {
                gemhedit (outimg//"["//(nextnd+1)//"]", "WAVTRAN", wcalfile, \
                    "", delete-)
            }

            # DQ header
            gemhedit (outimg//"["//(nextnd+2)//"]", "EXTNAME", l_dq_ext, "", \
                delete-)
            gemhedit (outimg//"["//(nextnd+2)//"]", "EXTVER", 1, "", delete-)
            if (l_fl_stran) {
                gemhedit (outimg//"["//(nextnd+2)//"]", "SDISTNAM", scalfile, \
                    "", delete-)
            }
            if (l_fl_wavtran) {
                gemhedit (outimg//"["//(nextnd+2)//"]", "WAVTRAN", wcalfile, \
                "", delete-)
            }
        }

        # Update APID column in MEF
        tinfo(outimg//"[MDF]",ttout-)
        apid=0
        for (i=1; i<=tinfo.nrows; i+=1) {
            tabpar(outimg//"[MDF]","BEAM",i)
            if (int(tabpar.value) != -1) {
               apid=apid+1
               partab(apid,outimg//"[MDF]","APID",i)
            }
        }

        gemhedit (outimg//"[0]", "NSCIEXT", 1, "", delete-)
        gemdate ()
        gemhedit (outimg//"[0]", "GFTRANSF", gemdate.outdate,
        "UT Time stamp for GFTRANSFORM")
        gemhedit (outimg//"[0]", "GEM-TLM", gemdate.outdate,
        "UT Last modification with GEMINI")
    } #end of while loop over input image list
    scanfile1=""

    goto clean

error:
    status=1
    goto clean

    #Clean Up
clean:
    delete(temp1//","//temp2//","//temp3//","//wavlist,
        verify-, >& "dev$null")
    imdelete(scilistout//","//scopyout,verify-, >& "dev$null")
    if (l_fl_vardq) {
        imdelete(varlistout//","//vcopyout,verify-, >& "dev$null")
        imdelete(dqlistout//","//dcopyout,verify-, >& "dev$null")
    }
    scanfile1=""
    printlog("",l_logfile,l_verbose)
    if(status==0)
        printlog("GFTRANSFORM exit status: good",l_logfile,l_verbose)
    else
        printlog("GFTRANSFORM exit status: error",l_logfile,l_verbose)
    printlog("-------------------------------------------------------------------------------",
        l_logfile,l_verbose)
    printlog("",l_logfile,l_verbose)

end
