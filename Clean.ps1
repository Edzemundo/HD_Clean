# PowerShell script to completely clean, format, mount and eject a disk
# WARNING: This will destroy ALL data on the selected disk

function Show-Menu {
    Clear-Host
    Write-Host "=== Disk Management Tool ===" -ForegroundColor Cyan
    List-Disks
    Write-Host "1. Clean and format a disk" -ForegroundColor Yellow
    Write-Host "2. Eject a disk" -ForegroundColor Yellow
    Write-Host "3. Mount a drive" -ForegroundColor Yellow
    Write-Host "4. Re-list disks" -ForegroundColor Yellow
    Write-Host "5. Exit" -ForegroundColor Yellow
    Write-Host "=========================" -ForegroundColor Cyan
}

function List-Disks {
    Write-Host "`nAvailable disks:" -ForegroundColor Yellow
    Get-Disk | Format-Table Number, FriendlyName, Size, PartitionStyle
    Write-Host "`nPress Enter to continue..." -ForegroundColor Green
    Read-Host
}

function Eject-Disk {
    # List available disks
    # Write-Host "`nAvailable disks:" -ForegroundColor Yellow
    # Get-Disk | Format-Table Number, FriendlyName, Size, PartitionStyle

    # Get disk number from user
    $diskNumber = Read-Host "`nEnter the disk number to eject"
    
    # Validate disk exists
    $disk = Get-Disk -Number $diskNumber -ErrorAction SilentlyContinue
    if (-not $disk) {
        Write-Host "Disk $diskNumber does not exist." -ForegroundColor Red
        Write-Host "`nPress Enter to continue..." -ForegroundColor Green
        Read-Host
        return
    }

    # Check if it's the system disk
    $systemDisk = Get-Disk | Where-Object { $_.IsBoot -eq $true }
    if ($disk.Number -eq $systemDisk.Number) {
        Write-Host "ERROR: Cannot eject the system disk!" -ForegroundColor Red
        Write-Host "`nPress Enter to continue..." -ForegroundColor Green
        Read-Host
        return
    }

    try {
        Write-Host "`nAttempting to safely eject the drive..." -ForegroundColor Yellow
        
        # Create a Shell object to eject the drive
        $shell = New-Object -ComObject Shell.Application
        
        # Get volume information
        $volume = Get-Partition -DiskNumber $diskNumber | Get-Volume | Where-Object { $null -ne $_.DriveLetter }
        
        if ($volume) {
            $driveLetter = $volume.DriveLetter + ":"
            $driveObject = $shell.Namespace(17).ParseName($driveLetter)
            if ($driveObject) {
                $driveObject.InvokeVerb("Eject")
            }
        }
        
        # Set disk offline
        Set-Disk -Number $diskNumber -IsOffline $true
        Write-Host "Drive ejected successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "Error ejecting drive: $_" -ForegroundColor Red
        Write-Host "Please eject the drive manually through Windows." -ForegroundColor Yellow
    }

    Write-Host "`nPress Enter to continue..." -ForegroundColor Green
    Read-Host
}


function Mount-Drive {
    # Get the disk number from user
    $diskNumber = Read-Host "`nEnter the disk number to mount"
    
    # Validate disk exists
    $disk = Get-Disk -Number $diskNumber -ErrorAction SilentlyContinue
    if (-not $disk) {
        Write-Host "Disk $diskNumber does not exist." -ForegroundColor Red
        Write-Host "`nPress Enter to continue..." -ForegroundColor Green
        Read-Host
        return
    }

    # Check if the disk is online
    if ($disk.IsOffline) {
        Write-Host "The disk is currently offline. Attempting to bring it online..." -ForegroundColor Yellow
        
        try {
            Set-Disk -Number $diskNumber -IsOffline $false
            Write-Host "Disk $diskNumber is now online." -ForegroundColor Green
        } catch {
            Write-Host "Failed to bring the disk online: $_" -ForegroundColor Red
            Write-Host "`nPress Enter to continue..." -ForegroundColor Green
            Read-Host
            return
        }
    }

    # Ask for mount options
    Write-Host "`nMount Options:" -ForegroundColor Yellow
    Write-Host "1. Assign drive letter" -ForegroundColor Yellow
    Write-Host "2. Mount to empty folder" -ForegroundColor Yellow
    $mountOption = Read-Host "Select mount option (1 or 2)"

    # Create a new partition if necessary
    $partition = Get-Partition -DiskNumber $diskNumber | Where-Object { $_.DriveLetter -eq $null }
    if (-not $partition) {
        Write-Host "No unallocated space found on the disk." -ForegroundColor Red
        return
    }

    if ($mountOption -eq "1") {
        # Show available drive letters
        $usedDriveLetters = (Get-Volume).DriveLetter
        $availableDriveLetters = 67..90 | Where-Object { $_ -notin $usedDriveLetters.foreach({ [int][char]$_ }) } | ForEach-Object { [char]$_ }
        Write-Host "`nAvailable drive letters: $($availableDriveLetters -join ', ')" -ForegroundColor Yellow
        
        $driveLetter = Read-Host "Enter desired drive letter (default: first available)"
        if ([string]::IsNullOrWhiteSpace($driveLetter)) { 
            $driveLetter = $availableDriveLetters[0] 
        }
        
        # Create the new partition and assign the drive letter
        New-Partition -DiskNumber $diskNumber -UseMaximumSize -DriveLetter $driveLetter
        Write-Host "Drive mounted successfully with letter $driveLetter!" -ForegroundColor Green
    }
    elseif ($mountOption -eq "2") {
        $mountPath = Read-Host "Enter the full path of an empty folder to mount to (e.g., C:\Mount\Disk1)"
        
        # Create the mount folder if it doesn't exist
        if (-not (Test-Path $mountPath)) {
            New-Item -ItemType Directory -Path $mountPath -Force
        }

        # Create the new partition and mount it to the specified folder
        $partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize
        Add-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPath
        Write-Host "Drive mounted successfully at $mountPath!" -ForegroundColor Green
    }
    else {
        Write-Host "Invalid option selected." -ForegroundColor Red
    }

    Write-Host "`nPress Enter to continue..." -ForegroundColor Green
    Read-Host
}



function Clean-AndFormatDisk {
    # Get disk number from user
    $diskNumber = Read-Host "`nEnter the disk number to clean and format"
    
    # Validate disk exists
    $disk = Get-Disk -Number $diskNumber -ErrorAction SilentlyContinue
    if (-not $disk) {
        Write-Host "Disk $diskNumber does not exist." -ForegroundColor Red
        Write-Host "`nPress Enter to continue..." -ForegroundColor Green
        Read-Host
        return
    }

    # Check if it's the system disk
    $systemDisk = Get-Disk | Where-Object { $_.IsBoot -eq $true }
    if ($disk.Number -eq $systemDisk.Number) {
        Write-Host "ERROR: Cannot clean the system disk!" -ForegroundColor Red
        Write-Host "`nPress Enter to continue..." -ForegroundColor Green
        Read-Host
        return
    }

    # Bring the disk online if it is offline
    if ($disk.OperationalStatus -eq 'Offline') {
        Write-Host "`nBringing disk $diskNumber online..." -ForegroundColor Yellow
        Set-Disk -Number $diskNumber -IsOffline $false
    }

    # Show current disk information
    Write-Host "`nSelected disk information:" -ForegroundColor Yellow
    $disk | Format-List FriendlyName, Size, PartitionStyle, NumberOfPartitions

    # Multiple warnings due to destructive nature
    Write-Host "`nWARNING! This will:" -ForegroundColor Red
    Write-Host "1. Delete ALL partitions and volumes on disk $diskNumber" -ForegroundColor Red
    Write-Host "2. Erase ALL data on the disk" -ForegroundColor Red
    Write-Host "3. Create a new partition and format it" -ForegroundColor Red
    Write-Host "`nThis operation CANNOT be undone!" -ForegroundColor Red
    $confirmation = Read-Host "Type 'Y' to confirm"

    if ($confirmation -eq "Y") {
        try {
            # Clear disk and convert to GPT
            Write-Host "`nCleaning disk..." -ForegroundColor Yellow
            Clear-Disk -Number $diskNumber -RemoveData -RemoveOEM -Confirm:$false
            Initialize-Disk -Number $diskNumber -PartitionStyle GPT

            # Get format preferences
            Write-Host "`nFile System Options: NTFS, FAT32, exFAT" -ForegroundColor Yellow
            $fileSystem = Read-Host "Enter desired file system (default: NTFS)"
            if ([string]::IsNullOrWhiteSpace($fileSystem)) { $fileSystem = "NTFS" }
            
            $label = Read-Host "Enter volume label (optional)"

            # Get mount point preferences
            Write-Host "`nMount Options:" -ForegroundColor Yellow
            Write-Host "1. Assign drive letter" -ForegroundColor Yellow
            Write-Host "2. Mount to empty folder" -ForegroundColor Yellow
            $mountOption = Read-Host "Select mount option (1 or 2)"

            # Create new partition using maximum size
            Write-Host "`nCreating new partition..." -ForegroundColor Yellow
            
            if ($mountOption -eq "1") {
                # Show available drive letters
                $usedDriveLetters = (Get-Volume).DriveLetter
                $availableDriveLetters = 67..90 | Where-Object { $_ -notin $usedDriveLetters.foreach({ [int][char]$_ }) } | ForEach-Object { [char]$_ }
                Write-Host "`nAvailable drive letters: $($availableDriveLetters -join ', ')" -ForegroundColor Yellow
                
                $driveLetter = Read-Host "Enter desired drive letter (default: first available)"
                if ([string]::IsNullOrWhiteSpace($driveLetter)) { 
                    $driveLetter = $availableDriveLetters[0] 
                }
                
                $partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize -DriveLetter $driveLetter
                $mountPoint = $driveLetter + ":"
            }
            else {
                # Mount to folder
                $mountPath = Read-Host "Enter the full path of an empty folder to mount to (e.g., C:\Mount\Disk1)"
                
                # Create mount folder if it doesn't exist
                if (-not (Test-Path $mountPath)) {
                    New-Item -ItemType Directory -Path $mountPath -Force
                }
                
                $partition = New-Partition -DiskNumber $diskNumber -UseMaximumSize
                Add-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPath
                $mountPoint = $mountPath
            }
            
            # Format the new partition
            Write-Host "Formatting new partition..." -ForegroundColor Yellow
            $volume = Format-Volume -Partition $partition `
                                  -FileSystem $fileSystem `
                                  -NewFileSystemLabel $label `
                                  -Confirm:$false

            Write-Host "`nOperation completed successfully!" -ForegroundColor Green
            Write-Host "New volume details:" -ForegroundColor Green
            if ($mountOption -eq "1") {
                $volume | Format-List DriveLetter, FileSystem, FileSystemLabel, Size, SizeRemaining
            }
            else {
                Write-Host "Mount Path: $mountPath" -ForegroundColor Green
                $volume | Format-List FileSystem, FileSystemLabel, Size, SizeRemaining
            }

            # Ask if user wants to eject the drive
            $ejectChoice = Read-Host "`nWould you like to safely eject the drive? (Y/N)"
            if ($ejectChoice.ToUpper() -eq 'Y') {
                try {
                    Write-Host "`nAttempting to safely eject the drive..." -ForegroundColor Yellow
                    
                    $shell = New-Object -ComObject Shell.Application
                    
                    if ($mountOption -eq "1") {
                        $driveObject = $shell.Namespace(17).ParseName($mountPoint)
                        if ($driveObject) {
                            $driveObject.InvokeVerb("Eject")
                            Write-Host "Drive ejected successfully!" -ForegroundColor Green
                        }
                    }
                    else {
                        # For mounted folders, remove the mount point first
                        Remove-PartitionAccessPath -DiskNumber $diskNumber -PartitionNumber $partition.PartitionNumber -AccessPath $mountPoint
                        Write-Host "Mount point removed and drive ejected successfully!" -ForegroundColor Green
                    }
                    
                    # Set disk offline after ejection
                    Set-Disk -Number $diskNumber -IsOffline $true
                }
                catch {
                    Write-Host "Error ejecting drive: $_" -ForegroundColor Red
                    Write-Host "Please eject the drive manually through Windows." -ForegroundColor Yellow
                }
            }
        }
        catch {
            Write-Host "`nError during operation: $_" -ForegroundColor Red
        }
    }
    else {
        Write-Host "`nOperation cancelled." -ForegroundColor Yellow
    }

    Write-Host "`nPress Enter to continue..." -ForegroundColor Green
    Read-Host
}

    
# Main program loop
do {
    Show-Menu
    $choice = Read-Host "`nEnter your choice (1-5)"
    
    switch ($choice) {
        "1" { Clean-AndFormatDisk }
        "2" { Eject-Disk }
        "3" { Mount-Drive }
        "4" { List-Disks }
	"5" { 
            Write-Host "`nExiting program..." -ForegroundColor Yellow
            exit	
        }

        default { 
            Write-Host "`nInvalid choice. Please try again." -ForegroundColor Red
            Write-Host "Press Enter to continue..." -ForegroundColor Green
            Read-Host
        }
    }
} while ($true)
