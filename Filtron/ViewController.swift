//
//  ViewController.swift
//  Filtron
//
//  Created by Jacob Hawken on 10/13/14.
//  Copyright (c) 2014 Jacob Hawken. All rights reserved.
//

import UIKit
import CoreImage
import CoreData
import OpenGLES

class ViewController: UIViewController, GalleryDelegate, UIImagePickerControllerDelegate, UINavigationControllerDelegate, UICollectionViewDataSource, UICollectionViewDelegate
{
    //MARK: Outlets and Properties
    @IBOutlet weak var imageView: UIImageView!
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var collectionViewBottomConstraint: NSLayoutConstraint!
    
    var context : CIContext?
    var originalThumbnail : UIImage?
    
    var filters = [Filter]()
    var filterThumbnails = [FilterThumbnail]()
    
    var delegate : GalleryDelegate?
    let imageQueue = NSOperationQueue()

    //MARK: - View methods
    override func viewDidLoad()
    {
        super.viewDidLoad()
        self.generateThumbnail()
        self.collectionView.dataSource = self
        self.imageQueue.maxConcurrentOperationCount = 7
        self.collectionView.delegate = self
        
        var options = [kCIContextWorkingColorSpace : NSNull()]
        var myEAGLContext = EAGLContext(API: EAGLRenderingAPI.OpenGLES2) 
        self.context = CIContext(EAGLContext: myEAGLContext, options: options)
        
        var appDelegate = UIApplication.sharedApplication().delegate as AppDelegate
        var seeder = CoreDataSeeder(context: appDelegate.managedObjectContext!)
        
        self.fetchFilters()
        
        if self.filters.count == 0
        {
            seeder.seedCoreData()
            self.fetchFilters()
        }
        
        self.resetFilterThumbnails()
        self.collectionView.reloadData()
        self.resetFilterThumbnails()
    }
    
    override func viewWillAppear(animated: Bool)
    {
        let press = UITapGestureRecognizer(target: self, action: Selector("photosPressed:"))
        self.imageView.addGestureRecognizer(press)
    }
    
    //MARK: Collection View methods
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int
    {
        if self.filters.count == 0 {
            println("i have not filters!!!")
        }
        
        return self.filters.count
    }
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell
    {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier("FILTER_CELL", forIndexPath: indexPath) as FilterThumbnailCell
        var filterThumbnail = self.filterThumbnails[indexPath.row]
        
        if filterThumbnail.filteredThumbnail != nil
        {
            cell.imageView.image = filterThumbnail.filteredThumbnail
        }
        else
        {
            cell.imageView.image = filterThumbnail.originalThumbnail
            filterThumbnail.generateThumbnail(
            { (image) -> Void in
                if let cell = collectionView.cellForItemAtIndexPath(indexPath) as? FilterThumbnailCell
                {
                    cell.imageView.image = image
                }
            })
        }
        return cell
    }
    
    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath)
    {
        self.imageQueue.addOperationWithBlock(
        { () -> Void in
            var image = CIImage(image: self.imageView.image)
            var imageFilter = CIFilter(name: self.filters[indexPath.row].name)
            imageFilter.setDefaults()
            imageFilter.setValue(image, forKey: kCIInputImageKey)
            
            //generate the results
            var result = imageFilter.valueForKey(kCIOutputImageKey) as CIImage
            var extent = result.extent()
            var imageRef = self.context!.createCGImage(result, fromRect: extent)
            
            NSOperationQueue.mainQueue().addOperationWithBlock(
                { () -> Void in
                    var filteredImage = UIImage(CGImage: imageRef)
                    self.imageView.image = filteredImage
                    self.exitFilteringMode()
                })
        })
    }
    
    //MARK: Actions and alerts
    func photosPressed(recognizer: UITapGestureRecognizer)
    {
        let alertController = UIAlertController(title: nil, message: "Photo Options", preferredStyle: UIAlertControllerStyle.ActionSheet)
        
        let randomImageAction = UIAlertAction(title: "Random Images", style: UIAlertActionStyle.Default)
        { (action) -> Void in
            self.performSegueWithIdentifier("SHOW_GALLERY", sender: self)
        }
        
        let photoLibraryAction = UIAlertAction(title: "Photo Library", style: UIAlertActionStyle.Default)
        { (action) -> Void in
            let imagePicker = UIImagePickerController()
            imagePicker.sourceType = UIImagePickerControllerSourceType.SavedPhotosAlbum
            imagePicker.allowsEditing = true
            imagePicker.delegate = self
            
            self.presentViewController(imagePicker, animated: true, completion: nil)
        }
        
        let cameraAction = UIAlertAction(title: "Camera", style: UIAlertActionStyle.Default)
            { (action) -> Void in
                let imagePicker = UIImagePickerController()
                imagePicker.sourceType = UIImagePickerControllerSourceType.Camera
                imagePicker.allowsEditing = true
                imagePicker.delegate = self
                
                self.presentViewController(imagePicker, animated: true, completion: nil)
        }
        
        let cancelAction = UIAlertAction(title: "Cancel", style: UIAlertActionStyle.Cancel)
        { (action) -> Void in
            
        }
        
        let filterAction = UIAlertAction(title: "Filters", style: UIAlertActionStyle.Default)
        { (action) -> Void in
            self.enterFilterMode()
        }
        
        alertController.addAction(randomImageAction)
        alertController.addAction(photoLibraryAction)
        alertController.addAction(cameraAction)
        alertController.addAction(filterAction)
        alertController.addAction(cancelAction)
        
        self.presentViewController(alertController, animated: true, completion: nil)
    }
    
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?)
    {
        if (segue.identifier == "SHOW_GALLERY")
        {
            var destinationVC = segue.destinationViewController as GalleryViewController
            destinationVC.delegate = self
        }
    }

    func imagePickerController(picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [NSObject : AnyObject])
    {
        let returnedImage = info[UIImagePickerControllerEditedImage] as? UIImage
        self.imageView.image = returnedImage
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
    func didTapOnPicture(image: UIImage)
    {
        self.imageView.image = image
        self.generateThumbnail()
        self.resetFilterThumbnails()
        self.collectionView.reloadData()
    }
    
    //MARK: - Other Functions
    
    func generateThumbnail()
    {
        let size = CGSize(width: 100, height: 100)
        UIGraphicsBeginImageContext(size)
        self.imageView.image?.drawInRect(CGRect(x: 0, y: 0, width: 100, height: 100))
        self.originalThumbnail = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
    }
    
    func fetchFilters()
    {
        var fetchRequest = NSFetchRequest(entityName: "Filter")
        
        var appDelegate = UIApplication.sharedApplication().delegate as AppDelegate
        var context = appDelegate.managedObjectContext
        
        var error: NSError?
        let fetchResults = context?.executeFetchRequest(fetchRequest, error: &error)
        if let filters = fetchResults as? [Filter]
        {
            println("filters: \(filters.count)")
            self.filters = filters
        }
    }
    
    func resetFilterThumbnails ()
    {
        var newFilters = [FilterThumbnail]()
        for var index = 0; index < self.filters.count; ++index
        {
            var filter = self.filters[index]
            var filterName = filter.name
            var thumbnail = FilterThumbnail(name: filterName, thumbnail: self.originalThumbnail!, queue: self.imageQueue, context: self.context!)
            newFilters.append(thumbnail)
        }
        self.filterThumbnails = newFilters
    }
    
    func enterFilterMode()
    {
        self.generateThumbnail()
        self.resetFilterThumbnails()
        self.collectionView.reloadData()
        self.collectionViewBottomConstraint.constant += self.collectionView.frame.height
        self.imageView.userInteractionEnabled = false
        
        UIView.animateWithDuration(0.4, animations:
        { () -> Void in
            self.view.layoutIfNeeded()
        })
        
        var doneButton = UIBarButtonItem(title: "Done", style: UIBarButtonItemStyle.Done, target: self, action: "exitFilteringMode")
        self.navigationItem.rightBarButtonItem = doneButton
    }
    
    func exitFilteringMode ()
    {
        self.collectionViewBottomConstraint.constant -= self.collectionView.frame.height
        
        UIView.animateWithDuration(0.4, animations:
        { () -> Void in
                self.view.layoutIfNeeded()
        })
        
        //remove the Done button
        self.navigationItem.rightBarButtonItem = nil
        self.imageView.userInteractionEnabled = true
    }
}

