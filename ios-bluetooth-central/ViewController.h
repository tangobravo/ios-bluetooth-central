//
//  ViewController.h
//  ios-bluetooth-central
//
//  Created by Simon Taylor on 23/09/2022.
//

#import <UIKit/UIKit.h>
#import <CoreBluetooth/CoreBluetooth.h>

@interface ViewController : UIViewController<CBCentralManagerDelegate, CBPeripheralDelegate, NSStreamDelegate>


@end

