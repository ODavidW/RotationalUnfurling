// Rotational unfurling V 1.1 
// Tested on GMS 3.43
// Requires python support in GMS
//
// Author: David Wahlqvist, January 7th, 2021
// 
// This script is designed to take a polycrystaline electron diffraction image and transform it into a form 
// that is more easily understood. This is done by doing a polar transform on the diffraction pattern with 
// a user defined, via a ROI, or pre-defined center. After this the polar transformed image is filtered by 
// removing everything with an intensity less than the column (radial) median multiplied by a constant limit
// which is by default 1.2. The filtered image is presented along with its column-wise sum as a lineplot.
//
// After requests, the script can now function directly on Fast Fourier Transforms generated within GMS. 
// The FFT is converted to real data via the modulus.

image MedianPy(image temp) {
	// Calls python to calculate the median of the input image. Requires Numpy to function.
	// The image that should be passed into the python script needs to be initialized within the function for 
	// some reason. I couldn't get it to work if it wasn't.

	image img = temp 

	// The number in which the value extracted from the python script needs to be initiated outside the python
	// script
	image out_img

	//Build PyScript:
	// I feel that it is somewhat useful to keep the line numbers as comments since this can help traceback
	// if any errors occur. The script starts by importing the required packages, numpy and DigitalMicrograph

	string pyScript
	pyScript = "#Python script for calculating the median of the image img" + "\n"							//1
	pyScript += "import DigitalMicrograph as DM" + "\n"													//2
	pyScript += "import numpy as np" + "\n"																//3

	//The image is passed into the python script via its ImageID.

	pyScript += "img = DM.FindImageByID("+ img.ImageGetID() + ")" + "\n"								//4
	pyScript += "if None == img:" + "\n"																//5
	pyScript += "	print( 'Error.No image passed in by DM-script sucessfully.' )" + "\n"				//6
	pyScript += "	exit(0)" + "\n"																		

	//The data contained in the image is extracted into a numpy array, and the median of this array is then
	//found. After this, the data type of the output needs to be changed to a double. 

	pyScript += "img_data = img.GetNumArray()" + "\n"
											//7
	pyScript += "img_data[img_data == 0] = 'nan'" + "\n"
	pyScript += "med = np.nanmedian(img_data,axis = 0)" + "\n"		//Maybe add this instead of line 8 if this works. 
	//pyScript += "med = np.median(img_data,axis = 0)" + "\n"														//8
	pyScript += "out_img = DM.CreateImage(med.copy(order = 'C'))" + "\n"																

	//When the script is done, the data needs to be passed back to DigitalMicrograph, which is done 
	//through TagGroups. In this case, the double med(see above) is saved as a Double in the tag
	//"Python_temp:out:Median".
	// TODO: implement a check for negative numbers and replace them with 0s BUG
	pyScript += "DM.GetPersistentTagGroup().SetTagAsLong('Python_temp:out:ID', out_img.GetID() )" + "\n"		//10
	pyScript += "out_img.ShowImage()" + "\n"

	//Always delete image variables used in python!!
	pyScript += "del out_img" + "\n"
	pyScript += "del img_data" + "\n"																	//11
	pyScript += "del img" + "\n"																		//12
	//--------------------------------------------------------------------------------------------------//
	//Python script ends here.

	//The python script is excecuted.
	ExecutePythonScriptString(pyScript,1)
	//This just checks if a value is present in the relevant TagGroup and extracts it to variable "median"
	number imgID
	if ( !GetPersistentTagGroup().TagGroupGetTagAsLong("Python_temp:out:ID",imgID))
		Throw("Python value passed out not found.")
	out_img = FindImageByID(imgID)
    
	//We need to delete the Tags we created to avoid cluttering up the PersistentTagGroup.
	GetPersistentTagGroup().TagGroupDeleteTagWithLabel("Python_temp")
	ImageDocument imgDoc = GetFrontImageDocument()
	imgdoc.ImageDocumentClose(0)

	Return out_img
}


void FilterMedian(image img, number lim) {
//This function filters the input image img by comparing with the median of each column in the image,
//with a tunable limit, lim. 
	image lineProj, medWarp
	number sx,sy, limit, notUsed, scalex
	string unitx
	
// notUsed is a variable that I use to indicate that this output is unused, and should be supressed,
//but I do not know how to supress outputs in this language... So therefore notUsed will be used
//instead.
	ImageGetDimensionCalibration(img, 0,notUsed,scalex,unitx,1)
	
//medWarp is set to be the same as img, which copies the size of img and all the data. All the data
//is then set to 0 to open it up for new data inputs. 
	medWarp = img
	medWarp = 0

	img.GetSize(sx, sy)

// A line projection is created and filled with the median values of the columns.
//	lineProj := RealImage( " ", 4, sx, 1 )
//	lineProj = 0
	
//	for( number i = 0; i<sx; i++) {
//		image temp := img[0,i,sy,i+1]
//		number med = MedianPy(temp) 
//		lineProj[i,0] = med
//	}
	lineProj = MedianPy(img)
//each row of medWarp is filled with the data from lineProj.
	medWarp = lineProj[icol, 0]
	
//The image img is filtered vs the median of each column, if the value in a pixel is higher than
//limit*median of that column, the value in the pixel is set to be the median. If the value is 
//lower than the limit*median, then the value is set to the proper value.  
	limit = lim
	medWarp = tert(img>limit*medWarp,medWarp,img)
	
//Subtracts medWarp from the input img. This means that values above limit*median will be positive
//and all other values will be 0. 
	img -= medWarp


// A line projection is done by summing over each column in the image img. 
	lineProj[icol,0] += img 
	
//Show the images with contrast adjustments to make them look better from the onset. 
	number max100Up = max(lineProj[0,50,1,sx])
	
	lineProj.showImage()
	lineProj.ImageSetDimensionCalibration(0, 0, scalex, unitx, 0)
	lineProj.SetName("Line projection of " + img.ImageGetLabel())
	ImageDisplay lineDisp = lineProj.ImageGetImageDisplay(0)
	LinePlotImageDisplaySetDoAutoSurvey(lineDisp, 0,0)
	LinePlotImageDisplaySetContrastLimits(lineDisp,0,max100Up)
	
	//Sets reasonable contrast limits for the polar transformed image. 
	img.showImage()
	img.SetName( "Filtered " + img.GetName())
	ImageDisplay filtDisp = img.ImageGetImageDisplay(0)
	ImageDisplaySetContrastLimits(filtDisp,0,max100Up/sy)
	filtDisp.ImageDisplaySetCaptionOn(1)
}

image RotationalUnfurling( image img, number cx, number cy) {
//This function transforms a cartesian coordinate image to a polar coordinate image by unwrapping it around the center. 
	
//notUsed is a variable where unused outputs are stored temporarily
	number notUsed, scale, sx, sy, rMax
	string unit	
	number deg_steps = 1080//720
	number r_steps = 1600//800

	img.GetSize(sx, sy)
	ImageGetDimensionCalibration(img, 0, notUsed, scale, unit, 0)

 // rMax: maximum distance in image from defined center
	rMax = SQRT(max(sx - cx, cx)**2 + max(sy - cy, cy)**2)        

 // Create transformed image container
	image img_polar := Realimage( "Polar transformed", 4, r_steps, deg_steps )        
	img_polar.ImageSetDimensionCalibration( 0, 0, scale*rMax/r_steps, unit, 0 )
	img_polar.ImageSetDimensionCalibration( 1, 0, 360/deg_steps, "degree", 0 )

	img_polar = img.warp( cx + icol * rMax/(r_steps-1)*cos(( irow/iheight ) * 2*Pi()), cy + icol * rMax/(r_steps-1)*sin(( irow/iheight ) * 2*Pi()) )

 return img_polar
}



//-------------------------------------Script----------------------------------------------------//

//Fetches the front image and makes sure that the center is defined by a ROI or has been previously set as an offset in the image.  
image img := GetFrontImage()

imageDisplay imgDisp = img.ImageGetImageDisplay(0)
ROI usedROI
number noROIs = imgDisp.ImageDisplayCountROIs()
number xOr = ImageGetDimensionOrigin(img,0)
number yOr = ImageGetDimensionOrigin(img,1)
number scale = ImageGetDimensionScale(img,0) //assumes that the scale is the same for both dimensions.

// Creating a dialog so that the limit can be changed if the alt-button is depressed.
TagGroup Tag_limit // This one apparently needs to be outside...
if(optiondown()){
	TagGroup dialog_items
	TagGroup dialog_tags = DLGCreateDialog("Change Limit", dialog_items)
	if(img.ImageIsDataTypeComplex()){
		dialog_items.DLGAddElement( DLGCreateRealField("Limit:", Tag_limit, 1.5, 8, 3 ) )
	}
	else {
		dialog_items.DLGAddElement( DLGCreateRealField("Limit:", Tag_limit, 1.2, 8, 3 ) )
	}
	if(!Alloc(UIframe).Init(dialog_tags).Pose() ) exit(0)
}

number limit = 1.2 // Limit is the filter strength, that is to say, everything above 1.2 * limit is kept, everything else is
//set to 0. 1.2 is standard for diffraction patterns. 

// Check if the image is complex, ie being run on a fourier transform. In this case, the limit is increased and
// the image is changed to be real-valued with the modulus of each pixel being set as the value of that pixel. 
if(img.ImageIsDataTypeComplex()){
	img.SetComplexMode(3)
	img.ConvertToLong()
	limit = 1.5 // 1.5 has in my experience worked well with fourier transforms that are not too out of focus. 
}
try {
	limit = Tag_limit.DLGGetValue()
}
catch {
	break
}
number centerY,centerX

if(xOr == 0 && yOr == 0) {
	if(noROIs != 1){
		showalert("Ensure that an oval or rectangular ROI is present on the frontmost image centered on the intended center of the rotational unfurling.",2)
		exit(0)
	}
	usedROI = imgDisp.ImageDisplayGetROI(0)
	if(!ROIIsRectangle(usedROI) && !ROIIsOval(usedROI)){
		showalert("Ensure that the ROI is oval or rectangular and centered on the intended center of unfurling.",2)
		exit(0)
	}
}
if(noROIs == 1) {
	// Finds the center of the user defined ROI.
	number top, bottom, left, right
	usedROI = imgDisp.ImageDisplayGetROI(0)
	
	if(ROIIsRectangle(usedROI)) {
		usedROI.ROIGetRectangle(top, left, bottom, right)
	}
	if(ROIIsOval(usedROI)) {
		usedROI.ROIGetOval(top, left, bottom, right)
	}

	centerX = (right + left)/2
	centerY = (bottom + top)/2
	
}
else {
	//Origin is essentially defined as 0 - offset, and as such will be negative, therefore we need
	//to multiply by -1.
	centerX = -xOr/scale
	centerY = -yOr/scale
	Result(centerX + " " + centerY + "\n")
}

//Converts the front image from 
image polar := RotationalUnfurling( img, centerX, centerY)
polar.SetName( "Polar transform of [" + img.imageGetLabel() + "]" )

//Filters the image and shows the line projection of the image. 
polar.FilterMedian(limit)

